# Web build of the app, served as static files by nginx. See Docs/hosting.md.

# ── Build ──────────────────────────────────────────────────────────────────
# No prebuilt image exists for this project's Flutter version, so install
# the exact pinned SDK (same version as .github/workflows/build.yml).
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.2
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-web && flutter precache --web

WORKDIR /app
# Dependencies first, so code-only changes reuse the cached pub get layer.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

# ── Serve ──────────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
