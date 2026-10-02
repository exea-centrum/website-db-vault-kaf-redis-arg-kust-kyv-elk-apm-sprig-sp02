FROM python:3.11-slim
RUN groupadd -g 1000 appuser && useradd -u 1000 -g appuser appuser
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["python","-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]
