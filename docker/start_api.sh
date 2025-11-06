#!/bin/bash
set -e

echo "⏳ Waiting for Postgres to be ready..."
while ! nc -z db 5432; do
  sleep 1
done
echo "✅ Postgres is ready!"

echo "🚀 Applying Alembic migrations..."
alembic upgrade head || { echo "❌ Alembic migration failed"; exit 1; }

echo "✅ Migrations applied successfully"

echo "🔥 Starting Gunicorn server..."
exec gunicorn -w 2 -b 0.0.0.0:8000 wsgi:app

