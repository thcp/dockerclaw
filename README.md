# OpenClaw

Hardened, containerized OpenClaw deployment following the [official Docker guide](https://docs.openclaw.ai/docker) and [security recommendations](https://docs.openclaw.ai/security).

## Why Docker?

OpenClaw runs an AI agent with tool access — file reads, web search, shell execution. Running it directly on the host means the agent operates with your user's full permissions: your files, your SSH keys, your credentials.

Docker isolates this:

- The container can **only** see `.openclaw/` (config) and `sandbox/` (shared workspace) — nothing else on your filesystem
- Port is bound to `127.0.0.1` only — no network exposure
- Linux capabilities are dropped (`NET_RAW`, `NET_ADMIN`), privilege escalation is blocked
- Memory and CPU limits prevent runaway resource consumption
- The agent workspace is restricted with `workspaceOnly: true` — even inside the container, tools can't escape the workspace directory

## Prerequisites

- Docker and Docker Compose v2
- Python 3 (for config generation)

## Quick start

```bash
./dockerclaw.sh setup
```

This single command runs the full pipeline:

1. **Onboard** — interactive setup (auth, provider selection)
2. **Harden** — sets file permissions (700/600) on config directory
3. **Configure** — reads `openclaw.ini`, generates a JSON patch, deep-merges into the config
4. **Start** — launches the gateway container
5. **Install skills** — pulls skills from ClawHub
6. **Dashboard** — prints the tokenized dashboard URL
7. **Pair** — monitors for browser pairing request and auto-approves (60s timeout)

Open the dashboard URL in your browser when prompted. The setup will detect and approve the pairing request automatically.

### Reset and start over

```bash
./dockerclaw.sh prune
./dockerclaw.sh setup
```

## Configuration

All settings live in two files:

- `openclaw.ini` — application config (gateway, tools, agents, hooks, skills)
- `dockerclaw.env` — container resource limits and Docker-level settings

Edit these files, then `prune` and `setup` to apply from scratch.

### Security hardening (from official recommendations)

| Setting | Value | Why |
|---|---|---|
| `tools.fs.workspaceOnly` | `true` | Restrict file access to workspace directory |
| `tools.exec.security` | `deny` | Disable shell execution |
| `tools.exec.ask` | `always` | Require approval for any exec |
| `tools.elevated.enabled` | `false` | Disable privileged operations |
| `tools.deny` | automation, runtime, sessions | Block dangerous control-plane tools |
| `logging.redactSensitive` | `tools` | Redact secrets in tool output logs |
| `discovery.mdns.mode` | `minimal` | Reduce info disclosure on LAN |
| File permissions | 700/600 | Config directory and files restricted to owner |

### Memory and compaction

| Setting | Value | Why |
|---|---|---|
| `compaction.memoryFlush.enabled` | `true` | Flush durable memories to disk before context compaction |
| `memorySearch.experimental.sessionMemory` | `true` | Index session transcripts for cross-session recall |
| `memorySearch.sources` | `memory, sessions` | Search both memory files and session history |

### Hooks

- **boot-md** — loads a context file at session startup
- **session-memory** — auto-saves and recalls memory across sessions

### Container hardening (docker-compose.yml)

| Measure | Implementation |
|---|---|
| Network isolation | Port bound to `127.0.0.1` only |
| Capability dropping | `NET_RAW`, `NET_ADMIN` dropped |
| Privilege escalation | `no-new-privileges: true` |
| Resource limits | Configurable via `dockerclaw.env` (default 8 GB / 2 CPUs) |
| Health monitoring | `/healthz` endpoint checked every 30s |
| Filesystem isolation | Only `.openclaw/` and `sandbox/` mounted |

## Commands

```
./dockerclaw.sh <command>

  setup      — onboard + configure + start + pair (reads from openclaw.ini)
  prune      — remove all containers, volumes, and config
  start      — start the gateway
  stop       — stop all containers
  restart    — restart the gateway
  logs       — tail gateway logs
  status     — show container status
  get-token  — print the gateway auth token
  config     — manage configuration (pass args to openclaw-cli)
  skills     — manage skills (pass args to openclaw-cli)
  dashboard  — print dashboard URL and approve device pairing
  cli        — run any openclaw-cli command
```

## Architecture

```
dockerclaw.sh         — CLI wrapper (setup, lifecycle, config, pairing)
openclaw.ini          — declarative app config (all settings in one place)
dockerclaw.env        — container resource limits and Docker settings
scripts/ini2json.py   — converts ini to JSON patch
docker-compose.yml    — official service definitions (gateway + cli)
.openclaw/            — runtime config and data (gitignored)
sandbox/              — shared host directory mounted into workspace
```

### How config works

```
openclaw.ini → ini2json.py → JSON patch → deep-merge into .openclaw/openclaw.json
```

No containers are spawned for configuration. The ini is converted to a JSON patch on the host and merged directly into the config file. Skills are the only post-start step (they need ClawHub network access).

### How device pairing works

The Control UI requires device pairing as a security measure. In Docker, browser connections arrive from the Docker bridge network, not loopback, so auto-approval doesn't apply. The `setup` and `dashboard` commands handle this by detecting pending pairing requests via `openclaw-cli devices list` and approving them with `openclaw-cli devices approve`.

## References

- [Official Docker docs](https://docs.openclaw.ai/docker)
- [Security hardening guide](https://docs.openclaw.ai/security)
- [Agent workspace isolation](https://docs.openclaw.ai/concepts/agent-workspace)
- [Memory configuration](https://docs.openclaw.ai/reference/memory-config)
- [Skills platform](https://docs.openclaw.ai/skills)
