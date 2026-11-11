# Single-container Reflex deployment for Render
ARG PORT=10000
ARG API_URL

FROM python:3.13-slim AS builder

# Install uv and bun (efficient package managers)
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /bin/uv
COPY --from=oven/bun:1 /usr/local/bin/bun /usr/local/bin/bun

ENV UV_COMPILE_BYTECODE=1 UV_NO_CACHE=1 PATH="/app/.venv/bin:$PATH"
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN uv venv && uv pip install -r requirements.txt

# Copy app code
COPY . .

# Build the static frontend
RUN REFLEX_API_URL=${API_URL:-http://localhost:$PORT} reflex export --frontend-only --no-zip

# Final image
FROM python:3.13-slim

# Install redis-server and caddy
RUN apt-get update -y && apt-get install -y --no-install-recommends redis-server caddy && rm -rf /var/lib/apt/lists/*

ARG PORT
ENV PATH="/app/.venv/bin:$PATH" PORT=$PORT REFLEX_REDIS_URL=redis://localhost PYTHONUNBUFFERED=1

WORKDIR /app

# Create non-root user
RUN adduser --disabled-password --gecos "" --home /app reflex && chown reflex /app

# Copy built assets and app
COPY --chown=reflex --from=builder /app/.venv .venv
COPY --chown=reflex --from=builder /app/.web/backend .web/backend
COPY --from=builder /app/.web/build/client /srv
COPY --chown=reflex . .

USER reflex

EXPOSE $PORT

# Start Caddy, Redis, and Reflex backend
CMD if [ -d alembic ]; then reflex db migrate; fi && \
    caddy start && \
    redis-server --daemonize yes && \
    exec reflex run --env prod --backend-only
