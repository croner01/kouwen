FROM python:3.12-slim

# System deps for baostock/pandas
RUN apt-get update -qq && apt-get install -y -qq curl && rm -rf /var/lib/apt/lists/*

# Python deps
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
    fastapi uvicorn "anthropic>=0.50.0" httpx python-dotenv

WORKDIR /app
COPY server.py /app/

EXPOSE 8080
CMD ["python3", "/app/server.py"]
