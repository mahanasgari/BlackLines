# syntax=docker/dockerfile:1

FROM node:22-alpine AS miniapp-build
WORKDIR /miniapp
COPY miniapp/package.json ./
RUN npm install
COPY miniapp/ ./
RUN npm run build

FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY main.py api_main.py start.sh ./
COPY --from=miniapp-build /miniapp/dist ./miniapp/dist
RUN chmod +x start.sh

CMD ["./start.sh"]
