# Ruflo Hub — Docker

A central MCP hub for your team: an HTTP wrapper around the Ruflo CLI (250+ tools), shared memory between Claude Code sessions, and a statusline backed by remote data. Active memory is local sql.js; PostgreSQL (pgvector) is an **optional** backup for `ruflo ruvector import/export`.

> 🇷🇺 Russian version: [docs/ru/README.md](docs/ru/README.md)

> **Guides:**
> - [Use cases](docs/use-cases.md) — scenarios for personal / team / multi-team use, pattern transfer between instances
> - [Ruflo usage guide](docs/ruflo-usage-guide.md) — practical distillation of the official README: what hooks do, which MCP tools you actually need, skills, 3-tier routing
> - [Swarm management](docs/swarm-management.md) — swarm operations: concept, lifecycle, ruflo@3.5.x quirks
> - [Multi-project work with ruflo](docs/ruflo-multiproject-guide.md) — knowledge transfer, task coordination, claims, hive-mind

```
Ruflo MCP (stdio) → Express proxy (Streamable HTTP) → port 3000
                          ↕
                    sql.js (/app/.swarm/memory.db)  ← active memory
                          ↕ (optional, manual commands)
                    PostgreSQL + pgvector (RuVector)  ← archive/bridge
```

## Quick start

### With PostgreSQL (full mode)

```bash
cp .env.example .env
# Edit .env — change POSTGRES_PASSWORD
docker compose up -d
```

`.env` must contain the line `COMPOSE_PROFILES=pg` (it's in `.env.example` by default) — this enables the `ruflo-db` service.

### Lean mode (without PostgreSQL)

```bash
cp .env.example .env
# Comment out or remove the COMPOSE_PROFILES=pg line
docker compose up -d
```

Only the ruflo services will start. Memory will be stored in sql.js (`/app/.swarm/memory.db`), persistent via a volume. Downside: `ruflo ruvector import/export` commands are unavailable — for transferring patterns between instances see alternatives in [docs/use-cases.md](docs/use-cases.md).

Server: `http://localhost:3000/mcp`

## Embedding as a service

The `jazzmax/ruflo-hub` image can be added to any existing `docker-compose.yml`.

### Variant A: with your own PostgreSQL (pgvector)

If your project doesn't yet have PostgreSQL with pgvector:

```yaml
services:
  # ... your services ...

  ruflo:
    image: jazzmax/ruflo-hub:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      RUFLO_PORT: 3000
      POSTGRES_HOST: ruflo-db
      POSTGRES_PORT: 5432
      POSTGRES_DB: ruflo
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme
    depends_on:
      ruflo-db:
        condition: service_healthy

  ruflo-db:
    image: pgvector/pgvector:pg17
    restart: unless-stopped
    environment:
      POSTGRES_DB: ruflo
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme
    volumes:
      - ruflo-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ruflo"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  ruflo-pgdata:
```

### Variant B: connect to an existing PostgreSQL

If PostgreSQL (with pgvector) already exists in the project:

```yaml
services:
  # ... your existing postgres ...
  # postgres:
  #   image: pgvector/pgvector:pg17
  #   ...

  ruflo:
    image: jazzmax/ruflo-hub:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      RUFLO_PORT: 3000
      POSTGRES_HOST: postgres        # name of your PostgreSQL service
      POSTGRES_PORT: 5432
      POSTGRES_DB: ruflo             # a separate database for ruflo
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme
    depends_on:
      postgres:
        condition: service_healthy
```

> PostgreSQL must have the pgvector extension. The `pgvector/pgvector:pg17` image ships with it.
> A plain `postgres:17` without pgvector will not work.

### Variant C: external PostgreSQL (outside Docker)

```yaml
services:
  ruflo:
    image: jazzmax/ruflo-hub:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      RUFLO_PORT: 3000
      POSTGRES_HOST: 192.168.1.100   # IP of your server
      POSTGRES_PORT: 5432
      POSTGRES_DB: ruflo
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme
```

### Healthcheck

The image has a built-in healthcheck. Other services can depend on ruflo:

```yaml
services:
  my-app:
    image: my-app:latest
    depends_on:
      ruflo:
        condition: service_healthy
```

### Multiple teams — multiple instances

```yaml
services:
  ruflo-team-alpha:
    image: jazzmax/ruflo-hub:latest
    ports:
      - "3001:3001"
    environment:
      RUFLO_PORT: 3001
      POSTGRES_HOST: ruflo-db
      POSTGRES_DB: ruflo_alpha
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme

  ruflo-team-beta:
    image: jazzmax/ruflo-hub:latest
    ports:
      - "3002:3002"
    environment:
      RUFLO_PORT: 3002
      POSTGRES_HOST: ruflo-db
      POSTGRES_DB: ruflo_beta
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme

  ruflo-db:
    image: pgvector/pgvector:pg17
    environment:
      POSTGRES_USER: ruflo
      POSTGRES_PASSWORD: changeme
    volumes:
      - ruflo-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ruflo"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  ruflo-pgdata:
```

> With a shared PostgreSQL, each instance uses its own database (`ruflo_alpha`, `ruflo_beta`). Databases are created automatically on the first RuVector startup.

## Connecting clients

### Automatic setup (recommended)

A single command from the project root:

```bash
curl "http://your-server:3000/setup?token=YOUR_TOKEN&name=ruflo-team" | bash
```

Or with an explicit project path:

```bash
curl "http://your-server:3000/setup?token=YOUR_TOKEN&name=ruflo-team" | bash -s /path/to/project
```

#### `/setup` parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `token` | — | Bearer token for authorization (the server's `MCP_AUTH_TOKEN` value) |
| `name` | `ruflo` | MCP server name in `.mcp.json` (determines the tool prefix: `mcp__<name>__*`) |
| `skills` | `1` | Install the skills/agents/commands bundle. `0` (`false`/`no`/`off`) disables it |

#### What the script does

1. Downloads hooks from the server (`auto-memory-hook.mjs`, `hook-handler.cjs`, `statusline.cjs`) into `.claude/helpers/`
2. Downloads and unpacks the `skills` + `agents` + `commands` bundle into `.claude/` (existing files are not overwritten — customizations are preserved; disable with `?skills=0`)
3. Creates `.claude-flow/ruflo.json` with the server URL and token (for the memory bridge)
4. Creates or amends `.mcp.json` with the MCP connection and authorization header
5. Creates `.claude/settings.json` with hook configuration (if the file doesn't already exist)
6. Verifies connectivity to the server

#### Examples

```bash
# Minimal (no auth, default name "ruflo")
curl http://192.168.1.100:3000/setup | bash

# With authorization
curl "http://192.168.1.100:3000/setup?token=572fd23e-ae2e-4e3b-9ea5-59e7a84c09a7" | bash

# Custom name per team
curl "http://192.168.1.100:3001/setup?token=TOKEN_A&name=ruflo-alpha" | bash
curl "http://192.168.1.100:3002/setup?token=TOKEN_B&name=ruflo-beta" | bash

# MCP bridge only, no skills/agents (legacy behavior)
curl "http://192.168.1.100:3000/setup?token=TOKEN&skills=0" | bash
```

#### ⚠️ Server on the same machine — use a hostname, not an IP

If ruflo-hub is running **on your laptop/desktop**, don't pin to an IP — it changes when you switch Wi-Fi/VPN. Use your machine's mDNS name (macOS and most Linux distros support `.local` out of the box via Bonjour/Avahi):

```bash
# macOS/Linux — hostname substitution
curl "http://$(hostname):3201/setup?token=TOKEN" | bash

# Explicit:
curl "http://MacBook-Pro-3.local:3201/setup?token=TOKEN" | bash
```

The same rule applies to `.claude-flow/ruflo.json` and `.mcp.json` — prefer storing `http://MacBook-Pro-3.local:3201/mcp` instead of an IP. Then the client keeps working across any network change.

**When `.local` is NOT suitable:**
- Clients outside the local network (another team's VPN, a remote VPS) — `hostname.local` won't resolve for them. You'll need public DNS (`ruflo.mycompany.com`) or a tunnel (Tailscale/Cloudflare Tunnel).
- Corporate networks with restrictive policies — Bonjour/mDNS may be disabled by IT. Check with `ping $(hostname)` from a client machine.

### Updating the bundle in an already-configured project

When new skills/agents/commands appear in the hub (or they get updated in the Docker image), you can update only the bundle — without re-running `/setup`, which would overwrite your configs:

```bash
# Current directory
curl http://your-server:3000/update-bundle | bash

# With an explicit project path
curl http://your-server:3000/update-bundle | bash -s /path/to/project

# Force-overwrite existing files
curl "http://your-server:3000/update-bundle?force=1" | bash
```

By default `tar -xzkf` (the `-k` flag) doesn't touch existing files — it only adds missing ones. With `?force=1` it's a full overwrite. Unlike `/setup`, this endpoint does not create `.claude-flow/ruflo.json`, `.mcp.json`, or `settings.json` — bundle only.

Don't forget to **restart Claude Code** in the project — skills load at SessionStart.

### Manual MCP connection

If you only need MCP without hooks or the memory bridge:

**Claude Code CLI:**
```bash
claude mcp add --transport http \
  -H "Authorization: Bearer YOUR_TOKEN" \
  ruflo-team http://your-server:3000/mcp
```

**Claude Desktop / VS Code / Cursor / JetBrains** (`.mcp.json`):
```json
{
  "mcpServers": {
    "ruflo-team": {
      "type": "http",
      "url": "http://your-server:3000/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_TOKEN"
      }
    }
  }
}
```

> An MCP connection gives you access to 250+ ruflo tools (memory, swarm, agents). Automatic setup via `/setup` additionally adds the **memory bridge** — pattern synchronization between Claude Code sessions.

## API endpoints

| Method | URL | Description |
|--------|-----|-------------|
| POST | `/mcp` | JSON-RPC proxy to ruflo MCP (main endpoint) |
| GET / DELETE | `/mcp` | Returns `405 Method Not Allowed` (MCP is POST-only) |
| GET | `/health` | Server status (`{"status":"ok","tools":257}`) |
| GET | `/stats` | Statusline summary: vectors, namespaces, `dbSizeKB`, swarm state, intelligence score |
| GET | `/setup` | Shell script for automatic project setup |
| GET | `/update-bundle` | Shell script for bundle-only updates (skills+agents+commands) |
| GET | `/bundle.tar.gz` | Tar.gz archive of the bundle (used by `/setup` and `/update-bundle`) |
| GET | `/templates` | List of available templates |
| GET | `/templates/:name` | Download a specific template |
| GET | `/.well-known/oauth-authorization-server` | OAuth discovery stub (returns 404 so clients fall back to no-auth) |
| GET | `/.well-known/oauth-protected-resource` | OAuth discovery stub (returns 404) |
| POST | `/register` | OAuth dynamic-client stub (returns 404) |

### POST /mcp — JSON-RPC

```bash
# Tool invocation
curl -X POST http://your-server:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"memory_store","arguments":{"key":"my-pattern","value":"pattern content","namespace":"my-project"}},"id":1}'

# Memory search
curl -X POST http://your-server:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"memory_search","arguments":{"query":"my search"}},"id":1}'

# List tools
curl -X POST http://your-server:3000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Authentication

If `MCP_AUTH_TOKEN` is set, all requests to `/mcp` require the header:

```
Authorization: Bearer <token>
```

The `/health`, `/stats`, `/setup`, `/update-bundle`, `/bundle.tar.gz`, `/templates`, and the OAuth discovery stubs are available without authorization.

## Memory Bridge

The bridge automatically synchronizes knowledge between Claude Code sessions and the ruflo server.

```
┌─────────────────────┐         ┌──────────────┐
│   Claude Code       │         │  Ruflo Server │
│                     │  HTTP   │              │
│  SessionStart ──────┼────────→│  memory_list │
│  (import)           │←────────┼  memory_get  │
│                     │         │              │
│  Stop ──────────────┼────────→│  memory_store│
│  (sync)             │         │              │
└─────────────────────┘         └──────────────┘
```

**At session start** (`auto-memory-hook.mjs import`):
- loads project patterns from the namespace named after the project directory
- loads shared patterns (common to all projects)
- emits them into the Claude Code session context

**At stop** (`auto-memory-hook.mjs sync`):
- reads Claude auto-memory files (`~/.claude/projects/.../memory/*.md`)
- pushes feedback and project entries to ruflo-hub
- available in the next session and from other projects

### Manual control

```bash
# Bridge status
node .claude/helpers/auto-memory-hook.mjs status

# Force sync
node .claude/helpers/auto-memory-hook.mjs sync

# Load patterns
node .claude/helpers/auto-memory-hook.mjs import
```

## Templates (templates/)

Files in `templates/` are served via `/templates/:name` and used by the `/setup` script:

| File | Purpose |
|------|---------|
| `auto-memory-hook.mjs` | Memory bridge — HTTP client for ruflo-hub |
| `hook-handler.cjs` | Claude Code hook handler (routing, status, edit tracking) |
| `statusline.cjs` | Statusline generator (git, model, context, cost, swarm) |
| `settings.json` | Template for `.claude/settings.json` with hook configuration |

### Server URL resolution

`auto-memory-hook.mjs` resolves the server URL in this priority order:

1. The `RUFLO_URL` environment variable
2. The `.claude-flow/ruflo.json` file (created by `/setup`)
3. Auto-discovery from a sibling `ruflo-hub/` project
4. Fallback: `http://localhost:3000/mcp`

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RUFLO_PORT` | `3000` | MCP server port |
| `POSTGRES_HOST` | `localhost` | PostgreSQL host |
| `POSTGRES_PORT` | `5432` | PostgreSQL port |
| `POSTGRES_DB` | `ruflo` | Database name |
| `POSTGRES_USER` | `ruflo` | User |
| `POSTGRES_PASSWORD` | `ruflo` | Password (change it!) |
| `MCP_AUTH_TOKEN` | — | Bearer token for authorization (if empty — no auth) |

## Backup

```bash
# Backup
docker exec <postgres-container> pg_dump -U ruflo ruflo > backup.sql

# Restore
cat backup.sql | docker exec -i <postgres-container> psql -U ruflo ruflo
```

## Updating ruflo

The `ruflo` package is pinned in the image at build time.

**Image rebuild (recommended):**
```bash
# Locally
docker compose build --no-cache
docker compose up -d

# For Docker Hub
docker build --no-cache -t jazzmax/ruflo-hub:latest .
docker push jazzmax/ruflo-hub:latest
```

**Update inside the container (fast, doesn't survive a restart):**
```bash
docker exec <ruflo-container> npm install -g ruflo@latest
docker restart <ruflo-container>
```

## Docker Hub

```bash
docker pull jazzmax/ruflo-hub:latest
```

## Build from source

```bash
git clone https://github.com/jazz-max/ruflo-hub.git
cd ruflo-hub
docker build -t jazzmax/ruflo-hub:latest .
docker push jazzmax/ruflo-hub:latest
```
