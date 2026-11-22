FROM python:3.13-slim

WORKDIR /app
COPY app/ .

USER 1000
EXPOSE 8080

CMD ["python", "-m", "http.server", "8080"]
