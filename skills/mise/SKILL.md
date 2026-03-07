---
name: mise
description: >
  Install and manage language runtime versions using mise. Use when you need
  to run language-specific tooling like mix format (Elixir), bundle exec
  (Ruby), or a specific Node/Python version not available system-wide.
  Runtimes installed via mise persist on the /paperclip volume across runs.
---

# mise Skill

`mise` is a polyglot runtime version manager (compatible with `.tool-versions` / `.mise.toml`). It replaces asdf, nvm, rbenv, pyenv, etc. with a single tool.

## How persistence works

The `HOME` directory inside the container is `/paperclip`, which is a Docker volume that persists across heartbeat runs. mise stores runtimes at `~/.local/share/mise/` — so runtimes you install survive container restarts and are available in subsequent heartbeats. The mise shims directory (`/paperclip/.local/share/mise/shims`) is on `$PATH` by default.

**Implication:** Only install a runtime once. On subsequent runs, it's already there.

---

## Basic commands

```bash
# Check what's installed
mise list

# Install a runtime
mise install erlang@27.2
mise install elixir@1.17.3-otp-27
mise install node@22
mise install python@3.12

# Use a version in the current shell
mise use erlang@27.2
mise use elixir@1.17.3-otp-27

# Check which version is active
mise current
mise current elixir
```

---

## Elixir / Erlang

Elixir requires a matching Erlang OTP version. Always install Erlang first.

```bash
# Install Erlang (OTP 27 recommended for Elixir 1.17.x)
mise install erlang@27.2

# Install Elixir (match the OTP suffix to your Erlang version)
mise install elixir@1.17.3-otp-27

# Activate for the current session
mise use erlang@27.2
mise use elixir@1.17.3-otp-27

# Verify
elixir --version
mix --version
```

### Common Mix tasks

```bash
# Format code
mix format

# Check formatting without changing files (useful in CI)
mix format --check-formatted

# Run tests
mix test

# Compile
mix compile

# Run a specific mix task
mix ecto.migrate
```

### Install Hex and Rebar (first time per Elixir version)

```bash
mix local.hex --force
mix local.rebar --force
```

### Fetch dependencies

```bash
mix deps.get
mix deps.compile
```

---

## Node.js

The system already has Node 20 installed. Use mise to install a different version if the project requires it.

```bash
mise install node@22
mise use node@22
node --version
```

---

## Python

```bash
mise install python@3.12
mise use python@3.12
python --version
pip install <package>
```

---

## Using .tool-versions or .mise.toml

If the project has a `.tool-versions` or `.mise.toml` in its root, mise will respect it:

```bash
# Install all versions declared in the project config
cd /path/to/project
mise install

# Then all tools are active for that directory
```

---

## Checking if a runtime is already installed

Before installing, check if it's already there to avoid redundant work:

```bash
# Returns empty if not installed, version string if installed
mise list elixir | grep "1.17.3"

# Or check if the command is available
which elixir && elixir --version || echo "not installed"
```

---

## Tips

- **First install is slow** — Erlang in particular takes a few minutes to compile (unless a precompiled binary is available for your platform). Subsequent runs are instant since runtimes are cached on the volume.
- **OTP compatibility** — Elixir version slugs include the OTP version (`elixir@1.17.3-otp-27`). The OTP version must match the Erlang you installed. Check [hex.pm/elixir-compatibility](https://hex.pm/docs/elixir_compatibility) if unsure.
- **Plugin list** — `mise plugins list-all` shows every available runtime plugin. Most common ones (erlang, elixir, node, python, ruby, go, rust) are built-in.
- **Global vs local** — `mise use --global` writes to `~/.config/mise/config.toml`. `mise use` without `--global` writes to the current directory's `.mise.toml`. Prefer `--global` in agent scripts unless the project already has a config file.
