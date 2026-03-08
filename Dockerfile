FROM node:lts-trixie-slim AS base
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl git gh \
    # passwd provides useradd — not included in bookworm-slim by default
    passwd \
    # JSON/YAML/text processing
    jq \
    # Fast search
    ripgrep fd-find \
    # Build tooling
    make unzip zip \
    # Python for scripting and tooling
    python3 python3-pip pipx \
    # Shell linting
    shellcheck \
    # Build deps for mise-managed runtimes (Erlang/Elixir/etc.)
    build-essential autoconf m4 \
    libssl-dev libncurses-dev \
  && rm -rf /var/lib/apt/lists/* \
  # Create non-root user here, in the same layer as passwd, so it is
  # guaranteed to be available in all downstream stages via inheritance.
  # Claude CLI refuses --dangerously-skip-permissions when run as root.
  && useradd --uid 1001 --home-dir /paperclip --create-home --shell /bin/bash paperclip
RUN corepack enable

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./
COPY cli/package.json cli/
COPY server/package.json server/
COPY ui/package.json ui/
COPY packages/shared/package.json packages/shared/
COPY packages/db/package.json packages/db/
COPY packages/adapter-utils/package.json packages/adapter-utils/
COPY packages/adapters/claude-local/package.json packages/adapters/claude-local/
COPY packages/adapters/codex-local/package.json packages/adapters/codex-local/
COPY packages/adapters/cursor-local/package.json packages/adapters/cursor-local/
COPY packages/adapters/openclaw/package.json packages/adapters/openclaw/
COPY packages/adapters/openclaw-gateway/package.json packages/adapters/openclaw-gateway/
COPY packages/adapters/opencode-local/package.json packages/adapters/opencode-local/
COPY packages/adapters/pi-local/package.json packages/adapters/pi-local/
RUN pnpm install --no-frozen-lockfile

FROM base AS build
WORKDIR /app
COPY --from=deps /app /app
COPY . .
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

FROM base AS production
WORKDIR /app
COPY --from=build /app /app
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest

# Install binary tools for agent use
# TARGETARCH is injected by Docker buildx (amd64 or arm64)
ARG TARGETARCH=arm64
ARG LOGCLI_VERSION=3.4.2
ARG MIMIRTOOL_VERSION=2.14.3

# yq — YAML processor (like jq but for YAML)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# logcli — Grafana Loki log querier
RUN curl -fsSL "https://github.com/grafana/loki/releases/download/v${LOGCLI_VERSION}/logcli-linux-${TARGETARCH}.zip" \
    -o /tmp/logcli.zip \
  && unzip /tmp/logcli.zip "logcli-linux-${TARGETARCH}" -d /tmp \
  && mv "/tmp/logcli-linux-${TARGETARCH}" /usr/local/bin/logcli \
  && chmod +x /usr/local/bin/logcli \
  && rm /tmp/logcli.zip

# mimirtool — Grafana Mimir / Prometheus metrics management
RUN curl -fsSL "https://github.com/grafana/mimir/releases/download/mimir-${MIMIRTOOL_VERSION}/mimirtool-linux-${TARGETARCH}" \
    -o /usr/local/bin/mimirtool && chmod +x /usr/local/bin/mimirtool

# AWS CLI v2 — ECS task role auth works automatically in ECS
RUN AWSARCH=$([ "${TARGETARCH}" = "arm64" ] && echo "aarch64" || echo "x86_64") \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWSARCH}.zip" -o /tmp/awscliv2.zip \
  && unzip /tmp/awscliv2.zip -d /tmp \
  && /tmp/aws/install \
  && rm -rf /tmp/aws /tmp/awscliv2.zip

# mise — polyglot runtime manager (elixir, erlang, ruby, python versions, etc.)
# Runtimes installed by agents persist on the /paperclip volume
RUN curl -fsSL "https://mise.jdx.dev/mise-latest-linux-${TARGETARCH}" \
    -o /usr/local/bin/mise && chmod +x /usr/local/bin/mise

# Copy entrypoint script that injects credentials before starting the server
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV NODE_ENV=production \
  HOME=/paperclip \
  PATH="/paperclip/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip \
  PAPERCLIP_INSTANCE_ID=default \
  PAPERCLIP_CONFIG=/paperclip/instances/default/config.json \
  PAPERCLIP_DEPLOYMENT_MODE=authenticated \
  PAPERCLIP_DEPLOYMENT_EXPOSURE=private

RUN chown -R paperclip:paperclip /app /paperclip

USER paperclip

VOLUME ["/paperclip"]
EXPOSE 3100

ENTRYPOINT ["/app/entrypoint.sh"]
