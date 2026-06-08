"""
KouWen Backend v2 — Full Skill Package support.
Installs entire skill directories (scripts + references + deps) from Gitee.
"""
import os
import json
import base64
import hashlib
import hmac
import secrets
import re
import yaml
import zipfile
import io
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional
from contextlib import asynccontextmanager

import asyncpg
import httpx
import jwt
from cryptography.fernet import Fernet
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from fastapi.responses import StreamingResponse

# ── Config ──
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://kouwen:kouwen123@postgres.kouwen:5432/kouwen")
JWT_SECRET = os.getenv("JWT_SECRET", secrets.token_hex(32))
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_HOURS = 720
AGENT_URL = os.getenv("AGENT_URL", "http://agent.kouwen:8080/api/v1/agent/chat")
SANDBOX_URL = os.getenv("SANDBOX_URL", "http://sandbox.kouwen:8080")
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY", Fernet.generate_key().decode())
PASSWORD_SALT = os.getenv("PASSWORD_SALT", secrets.token_hex(16))
SKILLS_PVC = Path(os.getenv("SKILLS_PVC", "/skills"))

fernet = Fernet(ENCRYPTION_KEY.encode() if isinstance(ENCRYPTION_KEY, str) else ENCRYPTION_KEY)
security = HTTPBearer()
pool: asyncpg.Pool = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    await _init_db(pool)
    yield
    await pool.close()

app = FastAPI(title="KouWen Backend", version="2.0.0", lifespan=lifespan)

# ── Models ──
class RegisterRequest(BaseModel):
    email: str; password: str; nickname: str = ""

class LoginRequest(BaseModel):
    email: str; password: str

class ApiKeySave(BaseModel):
    provider: str = "deepseek"; api_key: str
    base_url: str = "https://api.deepseek.com/anthropic"
    model: str = "deepseek-v4-pro"

class InstallSkillRequest(BaseModel):
    source_repo: str  # "ren02/trading-agents-plugin"
    skill_path: str = ""  # "skills/trading-analysis" — auto-detected if empty
    gitee_token: str = ""  # Optional Gitee personal access token

class CreateConversationRequest(BaseModel):
    skill_id: Optional[str] = None; title: Optional[str] = None

class SendMessageRequest(BaseModel):
    content: str; model: Optional[str] = None

# ── Auth helpers ──
def hash_password(pw: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", pw.encode(), PASSWORD_SALT.encode(), 100000).hex()

def verify_password(pw: str, h: str) -> bool:
    return hmac.compare_digest(hash_password(pw), h)

def create_token(user_id: str, email: str) -> str:
    return jwt.encode({
        "sub": user_id, "email": email,
        "exp": datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRE_HOURS),
        "iat": datetime.now(timezone.utc),
    }, JWT_SECRET, algorithm=JWT_ALGORITHM)

async def get_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    try:
        payload = jwt.decode(credentials.credentials, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        async with pool.acquire() as conn:
            row = await conn.fetchrow("SELECT id,email,nickname FROM users WHERE id=$1", payload["sub"])
            if not row: raise HTTPException(401)
            return dict(row)
    except jwt.ExpiredSignatureError: raise HTTPException(401, "Token expired")
    except jwt.InvalidTokenError: raise HTTPException(401, "Invalid token")

# ── DB Init ──
async def _init_db(pool):
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
                email TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
                nickname TEXT DEFAULT '', created_at TIMESTAMPTZ DEFAULT now()
            );
            CREATE TABLE IF NOT EXISTS api_keys (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                provider TEXT NOT NULL DEFAULT 'deepseek',
                key_encrypted TEXT NOT NULL, base_url TEXT, model TEXT,
                created_at TIMESTAMPTZ DEFAULT now()
            );
            CREATE TABLE IF NOT EXISTS skills (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL, version TEXT DEFAULT '1.0.0',
                author TEXT DEFAULT '', category TEXT DEFAULT '通用',
                yaml_content TEXT DEFAULT '', source_repo TEXT DEFAULT '',
                skill_yaml TEXT DEFAULT '', python_deps TEXT DEFAULT '[]',
                installed_at TIMESTAMPTZ DEFAULT now(),
                UNIQUE(user_id, name)
            );
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                skill_id TEXT, title TEXT,
                created_at TIMESTAMPTZ DEFAULT now(),
                updated_at TIMESTAMPTZ DEFAULT now()
            );
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
                conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
                content TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now()
            );
        """)

# ── Auth ──
@app.post("/api/v1/auth/register")
async def register(req: RegisterRequest):
    async with pool.acquire() as conn:
        if await conn.fetchval("SELECT id FROM users WHERE email=$1", req.email):
            raise HTTPException(409, "Email already registered")
        uid = await conn.fetchval(
            "INSERT INTO users (email,password_hash,nickname) VALUES ($1,$2,$3) RETURNING id",
            req.email, hash_password(req.password), req.nickname)
        return {"token": create_token(uid, req.email), "user": {"id": uid, "email": req.email, "nickname": req.nickname}}

@app.post("/api/v1/auth/login")
async def login(req: LoginRequest):
    async with pool.acquire() as conn:
        r = await conn.fetchrow("SELECT id,email,password_hash,nickname FROM users WHERE email=$1", req.email)
        if not r or not verify_password(req.password, r["password_hash"]):
            raise HTTPException(401, "Invalid credentials")
        return {"token": create_token(r["id"], r["email"]), "user": {"id": r["id"], "email": r["email"], "nickname": r["nickname"]}}

@app.get("/api/v1/auth/me")
async def me(user=Depends(get_user)):
    return {"user": user}

# ── API Keys ──
@app.post("/api/v1/keys")
async def save_key(req: ApiKeySave, user=Depends(get_user)):
    encrypted = fernet.encrypt(req.api_key.encode()).decode()
    async with pool.acquire() as conn:
        await conn.execute("DELETE FROM api_keys WHERE user_id=$1 AND provider=$2", user["id"], req.provider)
        await conn.execute("INSERT INTO api_keys (user_id,provider,key_encrypted,base_url,model) VALUES ($1,$2,$3,$4,$5)",
                          user["id"], req.provider, encrypted, req.base_url, req.model)
    return {"status": "ok"}

@app.get("/api/v1/keys/{provider}")
async def get_key(provider: str, user=Depends(get_user)):
    async with pool.acquire() as conn:
        r = await conn.fetchrow("SELECT key_encrypted,base_url,model FROM api_keys WHERE user_id=$1 AND provider=$2",
                               user["id"], provider)
    if not r: raise HTTPException(404)
    return {"provider": provider, "api_key": fernet.decrypt(r["key_encrypted"].encode()).decode(),
            "base_url": r["base_url"], "model": r["model"]}

# ── Skills (Full Package) ──
@app.get("/api/v1/skills")
async def list_skills(user=Depends(get_user)):
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id,name,version,author,category,source_repo,python_deps,installed_at FROM skills WHERE user_id=$1 ORDER BY installed_at DESC",
            user["id"])
    return {"skills": [dict(r) for r in rows]}

@app.post("/api/v1/skills/install")
async def install_skill(req: InstallSkillRequest, user=Depends(get_user)):
    """Download full skill directory from Gitee, store on PVC, install deps."""
    owner, repo = req.source_repo.split("/")[:2]
    
    async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
        # Get repo tree
        tree_url = f"https://gitee.com/api/v5/repos/{owner}/{repo}/git/trees/main?recursive=1"
        tree_params = {"access_token": req.gitee_token} if req.gitee_token else {}
        resp = await client.get(tree_url, params=tree_params)
        if resp.status_code != 200:
            raise HTTPException(400, f"Repo not accessible: {resp.status_code}")
        tree = resp.json().get("tree", [])
        if not tree:
            raise HTTPException(400, "Empty repository")

        # ── Detect skill entry points (Claude Code format) ──
        # Structured repos: skills/<name>/{SKILL.md, skill.yaml, skill.yml}
        # Flat repos:       <name>.md / <name>.yaml / <name>.yml at root
        # Directory repos:  <name>/{SKILL.md, skill.yaml, skill.yml} (any depth)
        SKIP_FILES = {"readme.md", "license.md", "pubspec.yaml", "pubspec.yml",
                     "analysis_options.yaml", ".pre-commit-config.yaml",
                     "skills-index.yaml", "_config.yml", "marketplace.json"}
        SKILL_ENTRY_NAMES = {"skill.md", "skill.yaml", "skill.yml"}

        # Detect if repo has a skills/ directory (structured mode)
        has_skills_dir = any(
            e.get("path", "").lower() in ("skills",) or e.get("path", "").lower().startswith("skills/")
            for e in tree
        )

        # Discover skill entry points from the repo tree
        skill_entries = {}  # skill_key -> {"entry_file": path, "files": set, "is_single": bool}
        for item in tree:
            if item.get("type") != "blob":
                continue
            path = item["path"]
            name_lower = path.rsplit("/", 1)[-1].lower()
            is_root = "/" not in path

            if has_skills_dir:
                # Structured mode: only under skills/ dir
                if not path.lower().startswith("skills/"):
                    continue
                if name_lower in SKILL_ENTRY_NAMES:
                    parent = path.rsplit("/", 1)[0]
                    skill_entries.setdefault(parent, {"entry_file": path, "files": set(), "is_single": False})
            else:
                # Flat mode: accept .md (exclude readme/license), .yaml, .yml
                if not name_lower.endswith((".md", ".yaml", ".yml")):
                    continue
                if name_lower in SKIP_FILES or name_lower.startswith("."):
                    continue

                if is_root:
                    # Root-level file = single-file skill
                    skill_entries[f"root:{path}"] = {"entry_file": path, "files": {path}, "is_single": True}
                elif name_lower in SKILL_ENTRY_NAMES:
                    # File in subdirectory that's a known entry name → dir-based skill
                    parent = path.rsplit("/", 1)[0]
                    skill_entries[parent] = {"entry_file": path, "files": set(), "is_single": False}

        if not skill_entries:
            raise HTTPException(404, "No skills found in this repository")

        # For structured repos: collect ALL supporting files under each skill dir
        if has_skills_dir:
            for item in tree:
                if item.get("type") != "blob":
                    continue
                path = item["path"]
                if not path.lower().startswith("skills/"):
                    continue
                for entry in skill_entries.values():
                    skill_path = entry["entry_file"].rsplit("/", 1)[0]
                    if path.startswith(skill_path + "/") or path == entry["entry_file"]:
                        entry["files"].add(path)

        installed = []
        for skill_key, entry in sorted(skill_entries.items())[:5]:
            entry_file = entry["entry_file"]
            is_single = entry["is_single"]
            all_files = list(entry["files"]) if entry["files"] else [entry_file]

            # Download all files via Gitee API
            skill_files = {}
            for fp in all_files:
                try:
                    api_url = f"https://gitee.com/api/v5/repos/{owner}/{repo}/contents/{fp}"
                    content_params = {"access_token": req.gitee_token} if req.gitee_token else {}
                    fr = await client.get(api_url, params=content_params)
                    if fr.status_code == 200:
                        import base64 as b64
                        skill_files[fp] = b64.b64decode(fr.json()["content"]).decode("utf-8")
                except Exception:
                    pass

            if not skill_files:
                continue

            # Determine skill name from entry file path
            if is_single:
                single_name = Path(entry_file).stem
                skill_name = single_name.replace("_", " ").replace("-", " ").title()
            else:
                parent_dir = entry_file.rsplit("/", 1)[0]
                skill_name = parent_dir.rsplit("/", 1)[-1]
                skill_name = skill_name.replace("_", " ").replace("-", " ").title()

            # Parse metadata from entry file(s) — support both SKILL.md and skill.yaml
            system_prompt = ""
            skill_meta = {"name": skill_name, "version": "1.0.0", "python_deps": []}
            for fp, content in skill_files.items():
                lc = fp.lower()
                # SKILL.md / claude.md → system prompt + YAML frontmatter
                if lc.endswith("skill.md") or lc.endswith("claude.md"):
                    system_prompt = content
                    if content.startswith("---"):
                        parts = content.split("---", 2)
                        if len(parts) >= 3:
                            try:
                                fm = yaml.safe_load(parts[1])
                                if fm:
                                    skill_name = fm.get("name", skill_name) or skill_name
                                    if fm.get("version"):
                                        skill_meta["version"] = str(fm["version"])
                                    if fm.get("python_deps"):
                                        skill_meta["python_deps"] = fm["python_deps"]
                            except Exception:
                                pass
                # skill.yaml / skill.yml → merge metadata (takes precedence)
                if lc.endswith("skill.yaml") or lc.endswith("skill.yml"):
                    try:
                        ym = yaml.safe_load(content)
                        if ym and isinstance(ym, dict):
                            skill_meta.update(ym)
                            if ym.get("system_prompt"):
                                system_prompt = ym["system_prompt"]
                            if ym.get("name"):
                                skill_name = ym["name"]
                    except Exception:
                        pass

            # Extract pip deps from all files
            python_deps = list(skill_meta.get("python_deps", []))
            for fp, content in skill_files.items():
                if fp.lower().endswith("requirements.txt"):
                    for line in content.split("\n"):
                        pkg = line.strip().split("#")[0].strip()
                        if pkg and not pkg.startswith("-"):
                            python_deps.append(pkg)

            # Store to PVC (preserve directory structure for scripts/ and references/)
            pvc_dir = SKILLS_PVC / user["id"] / skill_name
            pvc_dir.mkdir(parents=True, exist_ok=True)
            for fp, content in skill_files.items():
                # Keep subdirectory structure: skills/trading/scripts/run.py → pvc_dir/scripts/run.py
                if has_skills_dir:
                    # Strip the skills/<name>/ prefix to keep scripts/references subdirs
                    rel_path = fp[len(skill_key) + 1:] if fp.startswith(skill_key + "/") else Path(fp).name
                else:
                    rel_path = fp
                out_path = pvc_dir / rel_path
                out_path.parent.mkdir(parents=True, exist_ok=True)
                out_path.write_text(content, encoding="utf-8")
            (pvc_dir / "skill.yaml").write_text(
                yaml.dump(skill_meta, default_flow_style=False, allow_unicode=True),
                encoding="utf-8"
            )

            # Install pip deps in sandbox venv
            if python_deps:
                try:
                    async with httpx.AsyncClient(timeout=120) as sc:
                        await sc.post(
                            f"{SANDBOX_URL}/api/v1/skills/install-deps",
                            json={"user_id": user["id"], "skill_name": skill_name, "packages": python_deps}
                        )
                except Exception:
                    pass

            # Store to DB
            async with pool.acquire() as conn:
                sid = await conn.fetchval(
                    """INSERT INTO skills (user_id,name,version,author,category,yaml_content,source_repo,skill_yaml,python_deps)
                       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
                       ON CONFLICT (user_id,name) DO UPDATE
                       SET yaml_content=$6, skill_yaml=$8, python_deps=$9, installed_at=now()
                       RETURNING id""",
                    user["id"], skill_name, skill_meta.get("version", "1.0.0"),
                    skill_meta.get("author", owner), skill_meta.get("category", "通用"),
                    system_prompt or yaml.dump(skill_meta, allow_unicode=True),
                    req.source_repo,
                    yaml.dump(skill_meta, allow_unicode=True),
                    json.dumps(python_deps)
                )

            installed.append({
                "id": sid, "name": skill_name, "python_deps": python_deps,
                "files": len(skill_files),
                "files_list": [Path(f).name for f in skill_files]
            })

    return {"status": "installed", "skills": installed}

@app.delete("/api/v1/skills/{skill_id}")
async def delete_skill(skill_id: str, user=Depends(get_user)):
    async with pool.acquire() as conn:
        row = await conn.fetchrow("SELECT name FROM skills WHERE id=$1 AND user_id=$2", skill_id, user["id"])
        if not row: raise HTTPException(404)
        await conn.execute("DELETE FROM skills WHERE id=$1", skill_id)
    # Clean PVC
    import shutil
    pvc_dir = SKILLS_PVC / user["id"] / row["name"]
    shutil.rmtree(pvc_dir, ignore_errors=True)
    return {"status": "deleted"}

# ── Conversations ──
@app.get("/api/v1/conversations")
async def list_conversations(user=Depends(get_user)):
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id,skill_id,title,created_at,updated_at FROM conversations WHERE user_id=$1 ORDER BY updated_at DESC LIMIT 50",
            user["id"])
    return {"conversations": [dict(r) for r in rows]}

@app.post("/api/v1/conversations")
async def create_conversation(req: CreateConversationRequest, user=Depends(get_user)):
    async with pool.acquire() as conn:
        cid = await conn.fetchval(
            "INSERT INTO conversations (user_id,skill_id,title) VALUES ($1,$2,$3) RETURNING id",
            user["id"], req.skill_id, req.title or "新的对话")
    return {"id": cid}

@app.get("/api/v1/conversations/{conversation_id}/messages")
async def get_messages(conversation_id: str, user=Depends(get_user)):
    async with pool.acquire() as conn:
        if await conn.fetchval("SELECT user_id FROM conversations WHERE id=$1", conversation_id) != user["id"]:
            raise HTTPException(403)
        rows = await conn.fetch(
            "SELECT id,role,content,created_at FROM messages WHERE conversation_id=$1 ORDER BY created_at ASC",
            conversation_id)
    return {"messages": [dict(r) for r in rows]}

# ── Chat ──
@app.post("/api/v1/conversations/{conversation_id}/chat")
async def chat(conversation_id: str, req: SendMessageRequest, user=Depends(get_user)):
    async with pool.acquire() as conn:
        if await conn.fetchval("SELECT user_id FROM conversations WHERE id=$1", conversation_id) != user["id"]:
            raise HTTPException(403)

        key_row = await conn.fetchrow(
            "SELECT key_encrypted,base_url,model FROM api_keys WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1",
            user["id"])
        if not key_row: raise HTTPException(400, "请先配置 API Key")

        api_key = fernet.decrypt(key_row["key_encrypted"].encode()).decode()

        # Load skill if conversation has one
        skill_context = ""
        conv_row = await conn.fetchrow("SELECT skill_id FROM conversations WHERE id=$1", conversation_id)
        if conv_row and conv_row["skill_id"]:
            skill_row = await conn.fetchrow(
                "SELECT yaml_content,skill_yaml,python_deps FROM skills WHERE id=$1 AND user_id=$2",
                conv_row["skill_id"], user["id"])
            if skill_row:
                skill_context = (
                    f"\n\n## Skill Context\n"
                    f"预装脚本在 /skills/{user['id']}/{conv_row['skill_id']}/scripts/\n"
                    f"参考文档在 /skills/{user['id']}/{conv_row['skill_id']}/references/\n"
                    f"Python venv: /skills/{user['id']}/{conv_row['skill_id']}/.venv/\n"
                )

        rows = await conn.fetch(
            "SELECT role,content FROM messages WHERE conversation_id=$1 ORDER BY created_at ASC LIMIT 50",
            conversation_id)
        agent_messages = [{"role": r["role"], "content": r["content"]} for r in rows]
        agent_messages.append({"role": "user", "content": req.content})

        await conn.execute(
            "INSERT INTO messages (conversation_id,user_id,role,content) VALUES ($1,$2,'user',$3)",
            conversation_id, user["id"], req.content)
        await conn.execute("UPDATE conversations SET updated_at=now() WHERE id=$1", conversation_id)

    async def agent_stream():
        full_text = ""
        async with httpx.AsyncClient(timeout=300) as client:
            async with client.stream("POST", AGENT_URL, json={
                "api_key": api_key, "base_url": key_row["base_url"],
                "model": req.model or key_row["model"],
                "messages": agent_messages,
                "system": f"用户ID: {user['id']}\n沙盒可访问 /skills/ 目录{skill_context}",
                "max_tokens": 16384, "max_turns": 15,
            }, headers={"Accept": "text/event-stream"}) as resp:
                async for chunk in resp.aiter_bytes():
                    full_text += chunk.decode(errors="replace")
                    yield chunk

        # Save assistant response
        text_parts = []
        for line in full_text.split("\n"):
            if line.startswith("data: ") and '"content":' in line:
                try:
                    d = json.loads(line[6:])
                    if "content" in d: text_parts.append(d["content"])
                except Exception:
                    pass
        final = "".join(text_parts)
        if final:
            async with pool.acquire() as conn:
                await conn.execute(
                    "INSERT INTO messages (conversation_id,user_id,role,content) VALUES ($1,$2,'assistant',$3)",
                    conversation_id, user["id"], final)

    return StreamingResponse(agent_stream(), media_type="text/event-stream",
                            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

@app.get("/api/v1/health")
async def health():
    return {"status": "ok", "version": "2.0.0"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
