# ---- Stage 1: Build Next.js frontend ----
FROM node:22-alpine AS frontend-build

WORKDIR /build

COPY web/frontend/package.json web/frontend/package-lock.json ./web/frontend/
RUN cd web/frontend && npm ci

COPY web/frontend/ ./web/frontend/

ENV NEXT_PUBLIC_BACKEND_URL=""
RUN cd web/frontend && npm run build


# ---- Stage 2: Production runtime ----
FROM python:3.13-slim

# Install Node.js 22 and nginx
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs nginx supervisor && \
    apt-get purge -y curl gnupg && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps (no PySide6 / PyInstaller)
COPY requirements-deploy.txt ./
RUN pip install --no-cache-dir -r requirements-deploy.txt

# Copy Python source
COPY src/ ./src/
COPY web/backend/ ./web/backend/

# Copy built frontend + runtime deps
COPY --from=frontend-build /build/web/frontend/.next ./web/frontend/.next
COPY --from=frontend-build /build/web/frontend/public ./web/frontend/public
COPY --from=frontend-build /build/web/frontend/package.json ./web/frontend/package.json
COPY --from=frontend-build /build/web/frontend/package-lock.json ./web/frontend/package-lock.json
COPY --from=frontend-build /build/web/frontend/next.config.ts ./web/frontend/next.config.ts
COPY --from=frontend-build /build/web/frontend/node_modules ./web/frontend/node_modules

# Deployment configs
COPY nginx.conf /etc/nginx/conf.d/app.conf
RUN rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
COPY supervisord.conf ./

# Persistent data: credentials & schema symlinked to /data volume
RUN mkdir -p /data && \
    ln -sf /data/token.json /app/token.json && \
    ln -sf /data/apple_credentials.json /app/apple_credentials.json && \
    ln -sf /data/color_schema.json /app/color_schema.json && \
    ln -sf /data/.env /app/.env

EXPOSE 8080

CMD ["supervisord", "-c", "/app/supervisord.conf", "-n"]
