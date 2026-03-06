#!/bin/bash
set -euo pipefail

# ANTHROPIC_SETUP_TOKEN is passed directly as an env var — no file injection needed.
# The claude CLI picks it up natively.

# Inject Codex/OpenAI subscription credentials
if [[ -n "${CODEX_CREDENTIALS:-}" ]]; then
  mkdir -p /paperclip/.codex
  echo "$CODEX_CREDENTIALS" > /paperclip/.codex/credentials.json
  echo "[entrypoint] Codex credentials written to /paperclip/.codex/credentials.json"
fi

# Authenticate gh CLI with the GitHub token
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  echo "[entrypoint] gh CLI authenticated"
fi

exec node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
