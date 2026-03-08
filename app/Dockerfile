FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir boto3

COPY main.py .

CMD ["python", "main.py"]
