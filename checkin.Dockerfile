FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir \
    flask \
    requests

COPY check-in-page.py .

EXPOSE 5001

CMD ["python", "check-in-page.py"]
