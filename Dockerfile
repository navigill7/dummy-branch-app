FROM python:3.11-slim AS base

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1


RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


# Stage : 
FROM python:3.11-slim

WORKDIR /app

COPY --from=base /usr/local /usr/local


RUN apt-get update && apt-get install -y --no-install-recommends \
    netcat-traditional \
 && rm -rf /var/lib/apt/lists/*


COPY . .
COPY docker/start_api.sh /start_api.sh


RUN chmod +x /start_api.sh

EXPOSE 8000


ENV FLASK_ENV=production \
    PORT=8000 \
    PYTHONPATH=/app


CMD ["/start_api.sh"]

