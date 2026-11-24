# Current base image: passes the gate
# FROM python:3.13-slim
# Old base image blocked by the gate 
FROM python:3.11.4-slim-bookworm

WORKDIR /app
COPY app/ .

USER 1000
EXPOSE 8080

CMD ["python", "-m", "http.server", "8080"]
