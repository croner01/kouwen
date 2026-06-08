"""
KouWen Agent Service — Anthropic SDK based Agent with tool-use loop.
Supports DeepSeek/Claude via configurable base_url.
Tools: sandbox_execute (Python/Bash), web_search.
"""
import json
import os
import time
import asyncio
import httpx
from typing import AsyncGenerator
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
import anthropic
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    global http_client
    http_client = httpx.AsyncClient(timeout=120)
    yield
    await http_client.aclose()

app = FastAPI(title="KouWen Agent", version="1.0.0", lifespan=lifespan)
http_client = None  # Shared client, initialized in lifespan

# ── Sandbox endpoint (same k8s cluster, internal service) ──
SANDBOX_URL = os.getenv("SANDBOX_URL", "http://sandbox.kouwen:8080/api/v1/execute")

# ── Tool definitions (Anthropic format) ──
TOOLS = [
    {
        "name": "sandbox_execute",
        "description": "Execute Python or Bash code in a sandboxed environment. "
                       "Use this to fetch stock data, run calculations, or process files. "
                       "Python has baostock, akshare, pandas, numpy pre-installed. "
                       "For A-share stocks, prefix code with 'sh.' (Shanghai) or 'sz.' (Shenzhen), e.g. 'sh.603083'.",
        "input_schema": {
            "type": "object",
            "properties": {
                "language": {
                    "type": "string",
                    "enum": ["python", "bash"],
                    "description": "Script language"
                },
                "script": {
                    "type": "string",
                    "description": "Code to execute"
                },
                "timeout": {
                    "type": "integer",
                    "default": 30,
                    "description": "Max execution time in seconds (1-120)"
                }
            },
            "required": ["language", "script"]
        }
    },
    {
        "name": "web_search",
        "description": "Search the web for real-time information. "
                       "Use this for news, latest prices, sentiment, market events. "
                       "Returns top search results with titles and snippets.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query, e.g. '剑桥科技 603083 最新新闻'"
                },
                "count": {
                    "type": "integer",
                    "default": 5,
                    "description": "Number of results (1-10)"
                }
            },
            "required": ["query"]
        }
    }
]

SYSTEM_PROMPT_BASE = """你是 KouWen AI 助手，一个全能的金融分析 Agent。

你有以下工具可以使用：
1. **sandbox_execute** — 在沙盒中执行 Python/Bash 代码，用于获取股票数据、计算指标、回测策略
2. **web_search** — 搜索互联网获取实时新闻、舆情、最新价格

分析股票时请：
- 先用 sandbox_execute 获取历史K线、财务数据
- 再用 web_search 获取最新新闻和舆情
- 最后综合技术面+基本面+情绪面给出完整分析报告
- 给出明确的买入/持有/卖出建议和具体价位

请始终基于真实数据做判断，不确定的地方要明确标注。"""


class AgentRequest(BaseModel):
    api_key: str = Field(..., description="User's API key for the LLM provider")
    base_url: str = Field(default="https://api.deepseek.com/anthropic", description="Anthropic-compatible API base URL")
    model: str = Field(default="deepseek-v4-pro", description="Model name")
    messages: list[dict] = Field(..., description="Conversation messages")
    system: str = Field(default=SYSTEM_PROMPT_BASE, description="System prompt")
    max_tokens: int = Field(default=32768)
    max_turns: int = Field(default=15, description="Max agent tool-call turns")
    user_id: str = Field(default="", description="User ID for sandbox PVC access")
    skill_name: str = Field(default="", description="Skill name for sandbox PVC/venv access")


def sse_event(event: str, data: dict | str) -> str:
    """Format a Server-Sent Event."""
    if isinstance(data, dict):
        data = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata: {data}\n\n"


async def execute_sandbox(language: str, script: str, timeout: int = 30,
                          user_id: str = "", skill_name: str = "") -> dict:
    """Call the k8s sandbox service using shared HTTP client."""
    try:
        body = {"language": language, "script": script, "timeout": timeout}
        if user_id and skill_name:
            body["user_id"] = user_id
            body["skill_name"] = skill_name
        resp = await http_client.post(SANDBOX_URL, json=body)
        return resp.json()
    except Exception as e:
        return {"stdout": "", "stderr": str(e), "exit_code": -1}


async def execute_web_search(query: str, count: int = 5) -> dict:
    """Search via Jina Reader (free, no key needed)."""
    try:
        resp = await http_client.get(
            f"https://s.jina.ai/{query}",
            headers={"Accept": "text/plain", "User-Agent": "KouWen/1.0"}
        )
        # Parse Jina response into structured results
        text = resp.text[:3000]
        results = []
        for line in text.split("\n"):
            if line.startswith("Title:") or line.startswith("**Title:**"):
                results.append({"title": line.split(":", 1)[1].strip().strip("*")})
            elif (line.startswith("URL:") or line.startswith("**URL:**")) and results:
                results[-1]["url"] = line.split(":", 1)[1].strip().strip("*")
            elif (line.startswith("Description:") or line.startswith("**Description:**")) and results:
                results[-1]["snippet"] = line.split(":", 1)[1].strip().strip("*")
        return {"results": results[:count], "query": query}
    except Exception as e:
        return {"results": [], "error": str(e), "query": query}


async def agent_loop(
    api_key: str,
    base_url: str,
    model: str,
    messages: list[dict],
    system: str,
    max_tokens: int,
    max_turns: int,
    user_id: str = "",
    skill_name: str = "",
) -> AsyncGenerator[str, None]:
    """Main agent loop: call LLM (streaming SDK), handle tool use, repeat."""
    client = anthropic.AsyncAnthropic(
        base_url=base_url,
        api_key=api_key,
        max_retries=2,
    )

    system_prompt = [
        {"type": "text", "text": system},
        {"type": "text", "text": f"当前时间: {time.strftime('%Y-%m-%d %H:%M')}"}
    ]

    loop_messages = list(messages)  # copy

    for turn in range(max_turns):
        # ── Stream a response from the LLM ──
        try:
            stream = await client.messages.create(
                model=model,
                max_tokens=max_tokens,
                system=system_prompt,
                tools=TOOLS,
                messages=loop_messages,
                stream=True,
                timeout=httpx.Timeout(600.0),
            )
        except Exception as e:
            yield sse_event("error", {"message": str(e)})
            return

        text_accumulator = ""
        tool_uses: list[dict] = []
        current_tool_use = None  # {"id", "name", "_partial"}
        stop_reason = None

        async for sdk_event in stream:
            if sdk_event.type == "content_block_start":
                cb = sdk_event.content_block
                # Typed access (SDK >= 0.49); fallback to dict-like
                cb_type = cb.type if hasattr(cb, 'type') else cb.get('type', '')
                if cb_type == "text":
                    initial = getattr(cb, 'text', None) or cb.get('text', '')
                    text_accumulator = initial
                    if initial:
                        yield sse_event("text_delta", {"content": initial})
                elif cb_type == "tool_use":
                    current_tool_use = {
                        "id": getattr(cb, 'id', None) or cb.get('id', ''),
                        "name": getattr(cb, 'name', None) or cb.get('name', ''),
                        "_partial": "",
                    }

            elif sdk_event.type == "content_block_delta":
                delta = sdk_event.delta
                dt = delta.type if hasattr(delta, 'type') else delta.get('type', '')
                if dt == "text_delta":
                    chunk = getattr(delta, 'text', None) or delta.get('text', '')
                    text_accumulator += chunk
                    yield sse_event("text_delta", {"content": chunk})
                elif dt == "input_json_delta":
                    if current_tool_use is not None:
                        pj = getattr(delta, 'partial_json', None) or delta.get('partial_json', '')
                        current_tool_use["_partial"] += pj

            elif sdk_event.type == "content_block_stop":
                if current_tool_use is not None:
                    raw = current_tool_use["_partial"]
                    try:
                        parsed = json.loads(raw) if raw else {}
                    except json.JSONDecodeError:
                        parsed = {}
                    tool_uses.append({
                        "id": current_tool_use["id"],
                        "name": current_tool_use["name"],
                        "input": parsed,
                    })
                    current_tool_use = None

            elif sdk_event.type == "message_delta":
                # Extract stop_reason — different SDK versions differ on attribute vs dict
                d = sdk_event.delta
                stop_reason = (getattr(d, 'stop_reason', None)
                               or (d.get('stop_reason') if isinstance(d, dict) else None))

            # message_start / message_stop: nothing needed

        # ── Reconstruct full response content for loop history ──
        response_content = []
        if text_accumulator:
            response_content.append({"type": "text", "text": text_accumulator})
        for tu in tool_uses:
            response_content.append({
                "type": "tool_use",
                "id": tu["id"],
                "name": tu["name"],
                "input": tu["input"],
            })

        is_truncated = stop_reason == "max_tokens"

        if not tool_uses:
            yield sse_event("done", {
                "turns": turn + 1,
                "truncated": is_truncated,
                "truncation_reason": "max_tokens" if is_truncated else "",
            })
            return

        # ── Execute tools ──
        tool_results = []
        for tu in tool_uses:
            tool_id = tu["id"]
            tool_name = tu["name"]
            tool_input = tu["input"]

            yield sse_event("tool_use", {
                "id": tool_id,
                "name": tool_name,
                "input": tool_input,
            })

            if tool_name == "sandbox_execute":
                result = await execute_sandbox(
                    tool_input.get("language", "python"),
                    tool_input.get("script", ""),
                    tool_input.get("timeout", 30),
                    user_id=user_id, skill_name=skill_name,
                )
            elif tool_name == "web_search":
                result = await execute_web_search(
                    tool_input.get("query", ""),
                    tool_input.get("count", 5),
                )
            else:
                result = {"error": f"Unknown tool: {tool_name}"}

            yield sse_event("tool_result", {
                "id": tool_id,
                "name": tool_name,
                "result": result,
            })

            tool_results.append({
                "tool_use_id": tool_id,
                "type": "tool_result",
                "content": json.dumps(result, ensure_ascii=False),
            })

        # Append assistant message + tool results to conversation for next turn
        loop_messages.append({
            "role": "assistant",
            "content": response_content,
        })
        loop_messages.append({
            "role": "user",
            "content": tool_results,
        })

    # Max turns reached
    yield sse_event("done", {"turns": max_turns, "truncated": True, "truncation_reason": "max_turns"})


@app.get("/api/v1/health")
async def health():
    return {"status": "ok", "version": "1.0.0", "sandbox_url": SANDBOX_URL}


@app.post("/api/v1/agent/chat")
async def agent_chat(req: AgentRequest):
    """Run the agent loop and stream results as SSE."""
    return StreamingResponse(
        agent_loop(
            api_key=req.api_key,
            base_url=req.base_url,
            model=req.model,
            messages=req.messages,
            system=req.system,
            max_tokens=req.max_tokens,
            max_turns=req.max_turns,
            user_id=req.user_id,
            skill_name=req.skill_name,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        }
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
