#!/bin/bash
set -euo pipefail

# Bootstrap Claude credentials from ANTHROPIC_SETUP_TOKEN.
# The token alone is not enough — claude auth login must be run to exchange it
# for stored credentials in $HOME/.claude/. Without this step every agent run
# fails with "Not logged in" even when the env var is set.
if [[ -n "${ANTHROPIC_SETUP_TOKEN:-}" ]]; then
  echo "[entrypoint] Bootstrapping Claude credentials via setup token..."
  claude auth login \
    && echo "[entrypoint] Claude credentials bootstrapped." \
    || echo "[entrypoint] Warning: claude auth login failed — agent runs may fail."
fi

# Inject Codex/OpenAI subscription credentials
if [[ -n "${CODEX_CREDENTIALS:-}" ]]; then
  mkdir -p /paperclip/.codex
  echo "$CODEX_CREDENTIALS" > /paperclip/.codex/credentials.json
  echo "[entrypoint] Codex credentials written to /paperclip/.codex/credentials.json"
fi


# Bootstrap the first admin invite if requested
# Set BOOTSTRAP_CEO_BASE_URL to your public URL (e.g. https://app.example.com)
# The invite URL will be printed to container logs (e.g. CloudWatch).
# Safe to leave set permanently — skips automatically once an admin exists.
if [[ -n "${BOOTSTRAP_CEO_BASE_URL:-}" ]]; then
  echo "[entrypoint] Running bootstrap-ceo (base-url=${BOOTSTRAP_CEO_BASE_URL})"
  node --import ./cli/node_modules/tsx/dist/loader.mjs cli/src/index.ts auth bootstrap-ceo \
    --base-url "${BOOTSTRAP_CEO_BASE_URL}" || true
fi


exec node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
