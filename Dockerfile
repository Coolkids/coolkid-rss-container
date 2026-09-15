# syntax=docker/dockerfile:1.7

ARG BACKEND_REPO=https://github.com/Coolkids/coolkid-rss-webflux.git
ARG FRONTEND_REPO=https://github.com/Coolkids/coolkid-rss-web.git
ARG ANITOPY_REPO=https://github.com/Coolkids/anitopy4j.git

ARG BACKEND_REF=main
ARG FRONTEND_REF=main
ARG ANITOPY_REF=main


# =========================================================
# Backend Build
# =========================================================
FROM maven:3.9-eclipse-temurin-21-alpine AS backend-builder

ARG BACKEND_REPO
ARG BACKEND_REF
ARG ANITOPY_REPO
ARG ANITOPY_REF

RUN apk add --no-cache git

WORKDIR /build

RUN git clone \
    --depth 1 \
    --branch "${BACKEND_REF}" \
    "${BACKEND_REPO}" \
    backend

RUN git clone \
    --depth 1 \
    --branch "${ANITOPY_REF}" \
    "${ANITOPY_REPO}" \
    anitopy4j

WORKDIR /build/backend

RUN --mount=type=cache,target=/root/.m2 \
    mvn -f /build/anitopy4j/pom.xml install \
    -DskipTests \
    -B \
    && mvn clean package \
    -DskipTests \
    -B


# =========================================================
# Frontend Build
# =========================================================
FROM node:22-alpine AS frontend-builder

ARG FRONTEND_REPO
ARG FRONTEND_REF

RUN apk add --no-cache git

WORKDIR /build

RUN git clone \
    --depth 1 \
    --branch "${FRONTEND_REF}" \
    "${FRONTEND_REPO}" \
    frontend

WORKDIR /build/frontend

RUN npm install \
    && npm run build


# =========================================================
# Runtime
# =========================================================
FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache \
    nginx \
    supervisor \
    tzdata \
    ca-certificates \
    curl \
    && mkdir -p \
        /app \
        /app/logs \
        /run/nginx \
        /var/log/supervisor \
        /usr/share/nginx/html

WORKDIR /app


# ---------------------------------------------------------
# Backend
# ---------------------------------------------------------
COPY --from=backend-builder \
    /build/backend/target/coolkid-rss.jar \
    /app/coolkid-rss.jar


# ---------------------------------------------------------
# Frontend
# ---------------------------------------------------------
COPY --from=frontend-builder \
    /build/frontend/dist/spa/ \
    /usr/share/nginx/html/


# ---------------------------------------------------------
# Config
# ---------------------------------------------------------
COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf


# ---------------------------------------------------------
# Environment
# ---------------------------------------------------------
ENV TZ=Asia/Shanghai

ENV JAVA_OPTS=""

EXPOSE 80


# ---------------------------------------------------------
# Healthcheck
# ---------------------------------------------------------
HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=30s \
    --retries=3 \
    CMD curl -fsS http://127.0.0.1/ || exit 1


CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
