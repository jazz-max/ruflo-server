# Use Cases — ruflo-hub

Usage scenarios and recommended configurations. For deployment details see [README](../README.md), for swarm management — [swarm-management](./swarm-management.md), for multi-project work — [ruflo-multiproject-guide](./ruflo-multiproject-guide.md).

> **TL;DR for teams:** the main value is #2 «[Distributed team: spreading patterns](#2-distributed-team-spreading-patterns)». The rest are variations for specific configurations. Swarm and hive-mind are usually **not needed** — see [swarm-management.md](./swarm-management.md) for when they apply.

---

## 1. Personal developer instance

**Who:** a single developer on their own machine or laptop.
**Why:** a personal store of patterns, working prompts, and architectural decisions across all of their projects.

**Configuration:**
- One ruflo server on `localhost:3000` (or any port)
- MCP_AUTH_TOKEN can be omitted (local)
- In all of your projects — `curl http://localhost:3000/setup | bash`
- Default namespace = project directory name

**Example workflow:**
```bash
# In project A
cd ~/projects/my-app-a
curl "http://$(hostname):3000/setup" | bash

# In project B
cd ~/projects/my-app-b
curl "http://$(hostname):3000/setup" | bash
```

> **Don't use IP (`192.168.x.x`)** — when switching Wi-Fi/VPN the address changes and ruflo.json points to nowhere. `$(hostname)` on macOS returns `MacBook-Pro-3.local` — works stably via Bonjour/mDNS.

After this, Claude Code in both projects:
- Sees MCP tools `mcp__ruflo__*` (257 tools)
- On SessionStart automatically pulls its own patterns and shared patterns
- On Stop syncs new feedback/project notes back to the server

**Memory is preserved** in the named volume `ruflo-memory` → survives `docker compose up --build`.

---

## 2. Distributed team: spreading patterns

> **This is the main value of ruflo-hub for teams.** Not swarm, not hive-mind — but the fact that one developer finds a solution, and everyone else automatically gets it in their next Claude Code session.

**Who:** a team of 2–15 developers, each on their own git tree, syncing via push/pull, deploying in turn.
**Why:** accumulation of collective experience. Patterns found by one become available to all without manual exchange.

### How it works

```
┌─────────────────────────────────────────────────────────────┐
│ Dev A: working on a task, Claude runs into a problem        │
│                                                              │
│  1. Claude solves the task, saves an observation in          │
│     ~/.claude/projects/<proj>/memory/feedback_utf8.md:       │
│     "Always use UTF-8 BOM when writing CSV for Excel..."     │
│                                                              │
│  2. Stop hook → auto-memory-hook.mjs sync                    │
│     → memory_store into ruflo-hub, namespace="shared"        │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    ┌──────────────────┐
                    │   ruflo-hub   │
                    │   (shared)       │
                    └──────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ Dev B: the next day opens Claude Code in their project,     │
│ the task has nothing to do with CSV                          │
│                                                              │
│  1. SessionStart hook → auto-memory-hook.mjs import          │
│     → memory_list(namespace="shared") → receives patterns    │
│  2. All shared patterns end up in the new session context    │
│  3. When Dev B runs into CSV two weeks later — Claude        │
│     already knows about BOM. Dev B won't step on the rake.   │
└─────────────────────────────────────────────────────────────┘
```

**Key point:** neither Dev A nor Dev B does **anything special**. Everything happens via Claude Code hooks + memory bridge. Configure `/setup` once — the rest is automatic.

### Configuration

One ruflo server stood up on the team's internal server (`http://team-server:3000`):

```bash
# On the team server — once
git clone https://github.com/jazz-max/ruflo-hub && cd ruflo-hub
cp .env.example .env
# In .env: change MCP_AUTH_TOKEN to random, change POSTGRES_PASSWORD
docker compose up -d
```

Each developer at their end — one command per project:
```bash
cd ~/projects/my-project
curl "http://team-server:3000/setup?token=TOKEN&name=ruflo" | bash
```

### Namespace hygiene

Team convention:

| Namespace | What goes there | Who writes |
|-----------|------------------|-----------|
| `shared` | Patterns shared by the whole team (best practices, architectural decisions, pitfalls) | Everyone, via memory bridge |
| `project-<name>` | Specifics of one project (quirks, internal APIs) | Developers of that project |
| `<developer>-private` | Personal notes of a specific developer | Only themselves |

Important: ruflo **has no ACL at the namespace level** — everyone with the token sees everything. Namespace is a filter, not privacy. Do not store secrets in any form.

### What the team actually gets

- **A newcomer to the team is immediately at the senior level** in project knowledge. Patterns from `shared` + `project-*` land in their very first Claude Code session.
- **Incident postmortems** settle into memory. If Dev A burned prod with a bad migration and wrote feedback about it — Dev B will see the warning a month later.
- **Architectural decisions** don't dissolve in Slack and Linear channels. They stay available to Claude in the context of specific work.
- **Review comments** accumulate automatically. Dev A gets feedback on a PR → Claude remembers → Dev B writes similar code → Claude warns immediately.

### What the team does NOT get (so there are no false expectations)

- **Not real-time**. A pattern appears for Dev B in the **next** Claude Code session, not right now. Latency — from seconds to hours.
- **No automatic distillation**. In the base setup patterns are written "as is". If Claude auto-memory for Dev A had 20 small notes on one topic — Dev B will have the same 20 notes, not "the main thing". Advanced distillation requires enabling `hooks_intelligence_*` and ReasoningBank, see the "Advanced: auto-discovery" section.
- **No cross-language contextualization**. If Dev A writes in Python and Dev B in Go — Python patterns will land in Dev B's context. Claude itself understands what applies and what doesn't, but there is no language-level filtering at the ruflo layer.

### Swarm is NOT needed here

For this scenario `swarm_init`, `agent_spawn` and other ruflo coordination functions are **useless**. Pattern distribution goes only through memory + memory bridge. If your team has a sequential git workflow — you can forget about swarm entirely.

Swarm is only needed if one developer (in their own session) wants Claude to register agents in a shared DB **for history** — a rare case, see `docs/swarm-management.md`.

### Advanced: pattern auto-discovery

The base memory bridge is manual (Claude itself decides what to remember). Ruflo has infrastructure for **automatic** distillation:

| Mechanism | What it does |
|----------|-----------|
| `hooks_intelligence_trajectory-*` | Records the trajectory of Claude's actions (every tool call) |
| `hooks_intelligence_learn` | Extracts a generalized pattern from successful trajectories |
| ReasoningBank (skill `reasoningbank-intelligence`) | Distillation + verdict judgment + experience replay |
| `autopilot_learn/predict` | Continuous learning in the background |

This is **not enabled** in the base `/setup`. It requires:
1. Adding PreToolUse/PostToolUse hooks to `.claude/settings.json` calling trajectory-* tools
2. Setting up periodic consolidation (once a day — cron)
3. Handling verdicts (what counts as success/failure)

For most teams **the base memory-bridge is enough**. Advanced — when patterns reach the thousands and automatic grouping/removal of stale ones is needed.

### Downsides and things to keep in mind

- No ACL at the namespace level — everything is accessible to anyone with the token. Do not store secrets.
- The token needs to be rotated (variable `MCP_AUTH_TOKEN` on the server + `/setup` on clients).
- For now `auto-memory-hook.mjs` picks up only the stdlib Claude Code auto-memory format. Your own arbitrary note format won't go through it (you'd need to `memory_store` manually).

---

## 3. Multi-team installation (prod)

**Who:** an organization with several independent teams.
**Why:** each team wants its own isolated store of patterns, but with the ability to selectively share knowledge between teams.

**Configuration — option A: one server, different instances**

One machine, multiple ruflo containers on different ports (pattern from `docker-compose.override.yml`):

```yaml
services:
  ruflo-team-alpha:
    build: .
    ports: ["3001:3001"]
    environment:
      RUFLO_PORT: 3001
      POSTGRES_DB: ruflo_alpha
      MCP_AUTH_TOKEN: ${TOKEN_ALPHA}
    volumes:
      - ruflo-alpha-memory:/app/.swarm

  ruflo-team-beta:
    build: .
    ports: ["3002:3002"]
    environment:
      RUFLO_PORT: 3002
      POSTGRES_DB: ruflo_beta
      MCP_AUTH_TOKEN: ${TOKEN_BETA}
    volumes:
      - ruflo-beta-memory:/app/.swarm
```

Different tokens → different teams cannot read each other's memory via MCP.

**Configuration — option B: different machines**

- Team A — ruflo on the internal office server (`http://office-server:3000`)
- Team B — ruflo on a remote VPS (`https://ruflo.example.com`)
- Independent volumes, independent tokens

**This is the recommended prod scenario** — full network isolation + encryption (if HTTPS).

---

## 4. Selective pattern transfer between teams

**Who:** a developer working simultaneously in two teams.
**Why:** to transfer a specific case from one team's memory to another — not the whole store, but selectively.

**Configuration:**

In the `.mcp.json` of the **receiving** team's project, **both** servers are registered with different names:

```json
{
  "mcpServers": {
    "ruflo-source": {
      "type": "http",
      "url": "http://office-server:3000/mcp",
      "headers": { "Authorization": "Bearer TOKEN_A" }
    },
    "ruflo-target": {
      "type": "http",
      "url": "https://ruflo.example.com/mcp",
      "headers": { "Authorization": "Bearer TOKEN_B" }
    }
  }
}
```

Claude Code will see two groups of tools:
- `mcp__ruflo-source__memory_*` — read from team A
- `mcp__ruflo-target__memory_*` — write into team B

**Example request:**

> Find in `ruflo-source` a pattern about solving the encoding problem. Show its contents. If it fits — copy into `ruflo-target` in namespace `shared`, with metadata `{ imported_from: "team-alpha", imported_at: "<date>" }`.

Claude sequentially:
1. `mcp__ruflo-source__memory_search({ query: "encoding" })`
2. Shows the find to the user
3. `mcp__ruflo-source__memory_retrieve({ key: ... })` — full content
4. `mcp__ruflo-target__memory_store({ key, value, namespace: "shared", metadata })`

**Important:**
- The user must **see the content before writing** — so that secrets don't leak.
- Use namespace `shared` or `imported` — to distinguish your own from received.
- Always indicate source and date in metadata — so that half a year later you can tell whether the pattern is still relevant.

---

## 5. Mass transfer / memory backup

**When it's needed:**
- Migration to a new server
- Regular backup
- Merging two instances

**Tools:**

**A. JSON export/import (simple):**
```bash
docker exec ruflo-A ruflo memory export --output /tmp/mem.json
docker cp ruflo-A:/tmp/mem.json ./mem.json
docker cp ./mem.json ruflo-B:/tmp/mem.json
docker exec ruflo-B ruflo memory import --input /tmp/mem.json
```

**B. Via PostgreSQL (RuVector):**

If you want to use PG as a centralized store — provided both instances have access to the same PG instance:
```bash
# A → PG
docker exec ruflo-A ruflo ruvector import --input /app/.swarm/memory.db \
  --database ruflo --user ruflo --host ruflo-db

# PG → B
docker exec ruflo-B ruflo ruvector export --output /app/.swarm/memory.db \
  --database ruflo --user ruflo --host ruflo-db
```

Useful when instances are on the same machine and PG is already up in compose.

**C. SQL dump:**
```bash
docker exec ruflo-db pg_dump -U ruflo ruflo > backup.sql
```
For backing up PG, if manual `ruvector import` was done into it.

---

## 6. Memory bridge with Claude Code auto-memory

**How it works:** `templates/auto-memory-hook.mjs` is placed into a project via `/setup` and hooked up in `.claude/settings.json`:
- `SessionStart` → `node .claude/helpers/auto-memory-hook.mjs import` — pulls patterns from ruflo-hub into the new Claude Code session context.
- `Stop` → `node .claude/helpers/auto-memory-hook.mjs sync` — pushes notes from `~/.claude/projects/.../memory/*.md` back to ruflo-hub.

**What it gives you:**
- No manual `memory_store` — Claude Code writes itself.
- Patterns, feedback and project notes from Claude Code auto-memory automatically land on the server.
- Shared patterns appear in the context of **every** new session.

**Limitations:**
- The bridge syncs with **only one** server (the one in `.claude-flow/ruflo.json`). If `.mcp.json` lists multiple rufloes — the bridge still speaks only to one, the rest are accessible only via explicit MCP calls from Claude.

---

## What ruflo-hub does NOT do

1. **Does not actively store memory in PostgreSQL.** Memory lives in the sql.js file `/app/.swarm/memory.db` inside the container. The PG schema `claude_flow` is created in case of manual `ruvector import/export`, but `memory_store` writes nothing there. See [Architecture](#memory-architecture) below.

2. **Does not shard between instances automatically.** Two rufloes on different ports — two independent stores. Communication only via one of the transfer methods (see #4/#5).

3. **Does not rotate tokens.** If `MCP_AUTH_TOKEN` is compromised, you have to change it manually on the server and on every client (via re-running `/setup`).

4. **Does not encrypt content.** Everything that lands in `memory_store` is stored in plain text inside the container + in WAL. Do not store secrets.

5. **Does not provide ACL at the namespace level.** Everyone with MCP access to the instance sees all namespaces. If team isolation is needed — different instances with different tokens (#3).

---

## Memory architecture

```
┌───────────────────────────────────────────────────┐
│ Claude Code (at the developer)                    │
│   ↕ MCP over HTTP (/mcp, Bearer auth)             │
└────────────────────┬──────────────────────────────┘
                     │
┌────────────────────▼──────────────────────────────┐
│ Docker: ruflo-hub (server.mjs + ruflo CLI)     │
│                                                   │
│   Express proxy (/mcp, /health, /stats, /setup)   │
│       ↕ stdio                                     │
│   ruflo mcp start                                 │
│       ↕                                           │
│   sql.js (/app/.swarm/memory.db)    ← active      │
│                                       memory     │
└────────────────────┬──────────────────────────────┘
                     │ (only on manual command
                     │  ruflo ruvector import/export)
                     ↓
┌───────────────────────────────────────────────────┐
│ Docker: ruflo-db (pgvector/pgvector:pg17)         │
│ Schema claude_flow — backup/bridge for mass-migration│
└───────────────────────────────────────────────────┘
```

**Key fact:** PostgreSQL is optional for most use cases. Needed only if:
- Regular `ruvector import/export` is planned
- SQL access to vectors is required (analytics, BI)
- A future PG-backend for ruflo is expected (upstream plans, not yet implemented)

If not needed — the PG service can be removed from compose, freeing ~350MB RAM. See [README → Deployment options](../README.md).

---

## Pre-prod checklist

- [ ] `MCP_AUTH_TOKEN` is set and not default
- [ ] `POSTGRES_PASSWORD` is not default (if PG is used)
- [ ] Volume `ruflo-memory` (or custom) is mounted to `/app/.swarm` — so memory survives a rebuild
- [ ] HTTPS / reverse proxy (nginx, traefik) if the server is accessible from the internet
- [ ] Volume `ruflo-memory` backup on a schedule (`docker run --rm -v ruflo-memory:/data -v $(pwd):/backup alpine tar czf /backup/mem-$(date +%F).tgz /data`)
- [ ] Clients know the namespace rules (see #2, #3)
- [ ] Token rotation method is documented
