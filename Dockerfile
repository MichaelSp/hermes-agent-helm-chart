FROM ghcr.io/astral-sh/uv:0.11.24-python3.13-trixie@sha256:0d7a6c7f14e7959a9a81fe8aefe38f8521e2ae64358d42925afe72057b0fd814 AS uv_source

# Node 22 LTS source stage. Debian trixie's bundled nodejs is pinned to 20.x
# which reached EOL in April 2026 — we copy node + npm + corepack from the
# upstream node:22 image instead so we can stay on a supported LTS without
# waiting for Debian 14 (forky, ~mid-2027). Bookworm-based slim image used
# so the produced binary links against glibc 2.36, which runs cleanly on
# our Debian 13 (trixie, glibc 2.41) runtime.
FROM node:24-bookworm-slim@sha256:c2d5ade763cacfb03fe9cb8e8af5d1be5041ff331921fa26a9b231ca3a4f780a AS node_source

FROM debian:13.5

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    iputils-ping \
    tini \
    python3 \
    python-is-python3 \
    python3-dev \
    python3-venv \
    ripgrep \
    ffmpeg \
    gcc \
    g++ \
    make \
    cmake \
    pkg-config \
    libffi-dev \
    libolm-dev \
    procps \
    git \
    openssh-client \
    docker-cli \
    xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/
COPY --chmod=0755 --from=node_source /usr/local/bin/node /usr/local/bin/
COPY --from=node_source /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=node_source /usr/local/lib/node_modules/corepack /usr/local/lib/node_modules/corepack

RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

WORKDIR /opt/hermes

COPY package.json package-lock.json ./
# Copy workspace manifests first for better layer caching.
COPY web/package.json web/
COPY ui-tui/package.json ui-tui/
# hermes-ink is a file: workspace dependency, so npm needs the full tree.
COPY ui-tui/packages/hermes-ink/ ui-tui/packages/hermes-ink/

ENV npm_config_install_links=false

RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell && \
    npm cache clean --force

COPY pyproject.toml uv.lock ./
RUN touch ./README.md
RUN uv sync --frozen --no-install-project --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight

# Matrix deps from local extension image.
RUN /opt/hermes/.venv/bin/python -m ensurepip --default-pip 2>/dev/null || true
RUN uv pip install \
    --python /opt/hermes/.venv/bin/python \
    "mautrix[encryption]==0.21.0" \
    "Markdown==3.10.2" \
    "aiosqlite==0.22.1" \
    "asyncpg==0.31.0" \
    "aiohttp-socks==0.11.0"

COPY --chown=hermes:hermes . .

RUN cd web && npm run build && \
    cd ../ui-tui && npm run build

USER root
RUN chmod -R a+rX /opt/hermes && \
    chown -R hermes:hermes /opt/hermes/.venv /opt/hermes/ui-tui /opt/hermes/gateway /opt/hermes/node_modules

RUN uv pip install --no-cache-dir --no-deps -e "."

ARG HERMES_GIT_SHA=
RUN if [ -n "${HERMES_GIT_SHA}" ]; then \
        printf '%s\n' "${HERMES_GIT_SHA}" > /opt/hermes/.hermes_build_sha && \
        chown hermes:hermes /opt/hermes/.hermes_build_sha; \
    fi

ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_TUI_DIR=/opt/hermes/ui-tui
ENV HERMES_HOME=/opt/data

COPY --chmod=0755 docker/hermes-exec-shim.sh /opt/hermes/bin/hermes

ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"
RUN mkdir -p /opt/data
VOLUME [ "/opt/data" ]

USER hermes
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/hermes/.venv/bin/python", "-m", "hermes_cli.main"]
CMD ["gateway", "run"]
