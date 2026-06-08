FROM python:3.12-slim
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
    fastapi uvicorn asyncpg httpx pyjwt cryptography pydantic PyYAML
WORKDIR /app
COPY server.py /app/
EXPOSE 8080
CMD ["python3", "/app/server.py"]
