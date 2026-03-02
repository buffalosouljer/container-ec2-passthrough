FROM python:3.12-slim
RUN pip install --no-cache-dir boto3
RUN useradd -m app
USER app
WORKDIR /home/app
COPY app.py .
CMD ["python", "-u", "app.py"]
