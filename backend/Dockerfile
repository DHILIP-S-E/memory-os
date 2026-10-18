# One image for both processes:
#   API:    the default command below
#   worker: docker run <image> python -m app.worker
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app app
COPY alembic alembic
COPY alembic.ini .

EXPOSE 8080

# Apply any pending migrations, then serve. Safe to repeat on every start.
CMD ["sh", "-c", "python -m alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --proxy-headers"]
