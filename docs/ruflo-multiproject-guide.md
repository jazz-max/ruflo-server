# Ruflo — multi-project scenario for a development team

## What is Ruflo

Ruflo is a platform for orchestrating AI agents, operating through the MCP protocol. It includes semantic memory with vector embeddings, learning from patterns, task coordination, and cross-project knowledge search.

Data is stored locally in `.swarm/memory.db` (sql.js + HNSW indexes) at the root of each project.

## Architecture

```
~/.claude/projects/
├── project-a/memory/     ← Claude Code memory (markdown)
├── project-b/memory/
├── project-c/memory/
└── ...

Each project → its own .swarm/memory.db (local)
                    ↓
        Ruflo combines them into a single vector database
        with semantic search across all projects
```

## Key tools

### 1. Import memory from all projects

```
memory_import_claude (allProjects: true)
```

Pulls Claude Code memory from all projects into a single database with ONNX embeddings (all-MiniLM-L6-v2, 384-dim). After this, **semantic search** is available over knowledge from any project:

> "How did we solve the encoding problem?" → will find the answer even if the solution was in another project

### 2. Namespace isolation

`memory_store` supports `namespace` for logical data separation:

```
namespace: "project-a"        → knowledge of a specific project
namespace: "project-b"        → another project
namespace: "team-backend"     → shared knowledge of the backend team
namespace: "team-frontend"    → shared knowledge of the frontend team
namespace: "shared"           → cross-project solutions and architecture
namespace: "conventions"      → shared coding rules
```

### 3. Unified Search

```
memory_search_unified (query: "query text")
```

Searches simultaneously across Claude Code memory and AgentDB across all namespaces. Useful when you don't know which project contained the solution.

### 4. Task coordination

Two systems with different purposes:

**Tasks** — a simple tracker for ruflo's internal agents:

| Tool | Purpose |
|-----------|-----------|
| `task_create` | Create a task (type, priority, tags) |
| `task_assign` | Assign to an internal ruflo agent |
| `task_update / task_complete` | Update progress / complete |
| `task_list / task_summary` | List and summary by status |

**Claims** — coordination between people and agents (who is doing what, so work isn't duplicated):

| Tool | Purpose |
|-----------|-----------|
| `claims_claim` | Claim a task for yourself (human or agent) |
| `claims_handoff` | Hand off a task to someone else with progress and reason |
| `claims_mark-stealable / claims_steal` | Mark as free / take it for yourself |
| `claims_rebalance` | Rebalance load between agents |
| `claims_board` | Visual board (kanban by status) |

> **When to use what:** Tasks — for solo work and automation via ruflo agents. Claims — for team coordination, when multiple people or Claude Code sessions work in parallel.
>
> **Important:** Claims has no separate "create a task" command. A task is created automatically on the first `claims_claim` — you specify an `issueId` (e.g., a number from Linear or GitHub), and claims registers the claim. Claims is a registry of "who took what", not a task tracker.

| Tool | Purpose |
|-----------|-----------|
| `workflow_create / workflow_execute` | Templating recurring processes |

### 5. Learning from patterns

| Tool | Purpose |
|-----------|-----------|
| `hooks_intelligence_pattern-store` | Save a solution pattern |
| `hooks_intelligence_pattern-search` | Search for similar patterns |
| `autopilot_predict` | Prediction based on learned patterns |
| `guidance_recommend` | Recommendations on approach |

Ruflo learns from developer actions: which commands are run, which errors are fixed, which decisions are made. Patterns are stored with confidence scoring and temporal decay (half-life: 30 days).

## Team organization examples

### Option A: split by roles

```
Backend team:
  namespace: "team-backend"
  → ORM patterns, migrations, API contracts

Frontend team:
  namespace: "team-frontend"
  → components, state management, styles

Shared:
  namespace: "shared"
  → architectural decisions, integrations
```

### Option B: split by projects

```
namespace: "project-{name}"     → context of each project
namespace: "conventions"         → shared coding rules
namespace: "incidents"           → incident post-mortems
```

### Option C: hybrid

```
namespace: "project-{name}"              → project
namespace: "team-{role}"                 → team
namespace: "shared"                      → shared
namespace: "onboarding"                  → for new employees
```

## Hive-Mind (multi-agent mode)

Ruflo supports collective intelligence — several agents work in parallel within a single session:

```
hive-mind_init (topology: "mesh" | "hierarchical" | "ring" | "star")
hive-mind_spawn (count: N, role: "worker" | "specialist" | "scout")
hive-mind_memory — shared swarm memory
hive-mind_consensus — reaching consensus between agents
coordination_orchestrate — orchestration (parallel / sequential / pipeline / broadcast)
```

Applications: parallel code analysis, distributed code review, simultaneous work on multiple modules.

## Centralized server for a team

Local mode (`.swarm/` on each machine) limits ruflo to a single developer. A centralized MCP server removes this limitation.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  Dedicated server (ruflo-hub)                       │
│                                                     │
│  Ruflo MCP (stdio) → Express proxy (Streamable HTTP) │
│  ├── RuVector → PostgreSQL     ← shared knowledge base  │
│  └── port 3000 (/mcp)                               │
└───────────────┬─────────────────┬───────────────────┘
                │                 │
        ┌───────┘                 └────────┐
        ▼                                  ▼
  Developer A                        Developer B
  Claude Code                        Claude Code
  settings.json:                     settings.json:
  ruflo → http://server:3000         ruflo → http://server:3000
```

### Does the server need access to projects?

**No.** The Ruflo MCP server is the "brain" (knowledge base + coordinator), not the "hands".

```
Ruflo MCP server                         Claude Code (client)
─────────────────                        ────────────────────
Stores memory and patterns               Reads/writes project files
Coordinates tasks                        Runs git diff, analyzes code
Searches by embeddings                   Passes data to ruflo as parameters
Learns from patterns                     Receives recommendations from ruflo
Does NOT read project source code        Has full access to the project
```

All ruflo tools receive data **through request parameters** from Claude Code:

- `memory_store(key, value)` — client passes text, server saves
- `memory_search(query)` — client passes query, server searches by embeddings
- `analyze_diff(...)` — client passes diff, server analyzes
- `task_create(...)` — client describes the task, server coordinates

The server **does not access the filesystem of projects**, does not read source code, and does not touch git. This means:

- The server can be hosted on a separate machine without source code
- No need to mount projects or grant access to repositories
- More secure — the server stores only abstract knowledge, not code

> **Exception:** `memory_import_claude` — reads `~/.claude/projects/*/memory/*.md` from the local disk. Not used in centralized mode — clients push knowledge via `memory_store`.

### Running the MCP server

> **Important:** Ruflo MCP works only in stdio mode (v3.5). For network access, use [ruflo-hub](https://github.com/jazz-max/ruflo-hub) — a Docker container with an Express-based HTTP proxy (`server.mjs`) that wraps stdio into Streamable HTTP at `/mcp`.
>
> In stdio mode, claims, tasks, and hive-mind are visible between sessions **of one project**, but **not between projects** (each project has its own process). Details and the full table → [stdio mode limitations](#stdio-mode-limitations-important).

> **Why not `--transport http`?** The ruflo CLI accepts the `--transport http` flag, but in the code `startHttpServer()` does `import('@claude-flow/mcp')` — this package **does not exist** (not published to npm, it's a placeholder for future functionality). Startup will fail with `Cannot find module '@claude-flow/mcp'`. The only working transport is stdio. For network access you need an external proxy, and that's exactly what [ruflo-hub](https://github.com/jazz-max/ruflo-hub) does via its Express-based HTTP proxy (`server.mjs`).

**Method 1: Docker Compose** (recommended):

```bash
git clone https://github.com/jazz-max/ruflo-hub.git
cd ruflo-hub
cp .env.example .env
# Edit .env:
#   RUFLO_PORT=3000           — server port
#   POSTGRES_PASSWORD=...     — DB password
#   POSTGRES_DATA=ruflo-pgdata — volume for data
docker compose up -d

# Check
curl http://localhost:3000/health
```

> **Important:** The `jazzmax/ruflo-hub` image **does not contain PostgreSQL** — only Node.js, ruflo, the Express proxy (`server.mjs`), and postgresql-client. PostgreSQL is spun up in a separate container (`ruflo-db`) via docker-compose.

**Method 1b: Docker Hub image** (if PostgreSQL already exists):

```bash
# PostgreSQL with pgvector must be running and accessible.
# Plain postgres:17 without pgvector will not work — you need pgvector/pgvector:pg17.
docker run -d --name ruflo-personal \
  -p 3000:3000 \
  -e RUFLO_PORT=3000 \
  -e POSTGRES_HOST=192.168.1.100 \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_DB=ruflo \
  -e POSTGRES_USER=ruflo \
  -e POSTGRES_PASSWORD=mysecret \
  jazzmax/ruflo-hub:latest

# Check
curl http://localhost:3000/health
```

> `POSTGRES_HOST` — IP or hostname of an existing PostgreSQL server. When running in a Docker network, you can specify the container name (e.g., `postgres`). The RuVector schema (`claude_flow`) will be created automatically on first start.

`.env` parameters:

| Variable | Default | Description |
|---|---|---|
| `RUFLO_PORT` | `3000` | Port that the Express proxy (`server.mjs`) listens on |
| `POSTGRES_HOST` | `ruflo-db` | PostgreSQL host (in compose — the service name) |
| `POSTGRES_PORT` | `5432` | PostgreSQL port |
| `POSTGRES_DB` | `ruflo` | Database name |
| `POSTGRES_USER` | `ruflo` | DB user |
| `POSTGRES_PASSWORD` | `ruflo` | DB password (**must be changed!**) |
| `POSTGRES_DATA` | `ruflo-pgdata` | Docker volume for PostgreSQL data |

Inside the container:
```
Ruflo MCP (stdio) → Express proxy (Streamable HTTP) → port 3000 (/mcp)
                          ↕
                    PostgreSQL + pgvector (RuVector)
```

**Method 2: manual startup** (without Docker, if you need a custom setup):

The canonical proxy for this project is `server.mjs` from the [ruflo-hub](https://github.com/jazz-max/ruflo-hub) repo — clone it and run `node server.mjs` directly (it spawns `ruflo mcp start` as a stdio child and exposes Streamable HTTP at `/mcp`).

### Connecting clients

All clients connect to the `/mcp` endpoint (Streamable HTTP). Configuration is the same for all IDEs.

**Claude Code CLI:**
```bash
claude mcp add ruflo-team --url http://your-server:3000/mcp
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`),
**VS Code** (`.vscode/mcp.json`),
**Cursor** (`.cursor/mcp.json`),
**JetBrains** (Settings → Tools → AI Assistant → MCP):

```json
{
  "mcpServers": {
    "ruflo-team": {
      "url": "http://your-server:3000/mcp"
    }
  }
}
```

> For local development (without a centralized server) you can use stdio mode directly:
> ```json
> {
>   "mcpServers": {
>     "ruflo": {
>       "command": "npx",
>       "args": ["ruflo@latest", "mcp", "start"]
>     }
>   }
> }
> ```

> To enable a nice status bar in the terminal with ruflo counters in the project folder:
```bash
npx ruflo@latest init --only-claude 
```

### Storage options

| Option | Concurrent access | Scale | Recommendation |
|---------|---------------------|---------|--------------|
| SQLite (`.swarm/memory.db`) | Single-writer, locks | 1-2 people | For a single developer |
| PostgreSQL (RuVector) | Full, 52K+ inserts/sec | Team of any size | **For a team** |
| Git (commit `.swarm/`) | Manual, conflicts in binary files | 2-3 people | Last resort |

### RuVector PostgreSQL — why for a team

RuVector is ruflo's bridge to PostgreSQL with 77+ SQL functions for AI operations:

- **HNSW/IVF** indexing for vector search
- **52,000+ inserts/sec** — no SQLite locks
- **39 Attention mechanisms** — Multi-head, Flash, Sparse, Linear
- **15 types of GNN layers** — GCN, GAT, GraphSAGE
- **Self-Learning** — query optimizer with EWC++
- **Hyperbolic Embeddings** — Poincaré, Lorentz, Klein models

**Prerequisite:** install PostgreSQL on the server (apt, brew, Docker — any way). RuVector does not install PostgreSQL itself; it initializes the schema and AI functions in an existing database.

```bash
# 1. PostgreSQL is already installed and running
# 2. Create database and user (standard psql)
createdb ruflo_team
createuser ruflo_admin

# 3. Initialize RuVector schema (77+ AI functions, HNSW indexes)
npx ruflo ruvector init --database ruflo_team --user ruflo_admin

# Monitoring and maintenance
npx ruflo ruvector status --verbose
npx ruflo ruvector benchmark --iterations 1000
npx ruflo ruvector optimize --analyze
npx ruflo ruvector backup --output ./backup.sql
```

### Namespace organization for a team

```
namespace: "dev:{username}"           → developer's personal space
namespace: "project:{project-name}"   → project knowledge
namespace: "team:{team-name}"         → team conventions
namespace: "shared"                   → cross-project solutions
namespace: "incidents"                → incident post-mortems
namespace: "onboarding"               → for new employees
```

### How to invoke ruflo tools

Ruflo provides 80+ tools (for example, `memory_store`, `claims_board`, `analyze_diff-risk`). These are **MCP tools**, not bash commands — they cannot be typed directly in the terminal.

**Method 1: Via Claude Code (primary)**

Just ask Claude in natural language:
```
> Show the ruflo task board
> Save to ruflo: solution to the encoding problem — use iconv
> Assess the risks of my diff through ruflo
```
Claude will invoke the appropriate MCP tool with the correct parameters itself.

**Method 2: Via the ruflo CLI (partial coverage)**

Some tools have CLI equivalents:
```bash
npx ruflo memory store --key "fix" --value "solution description"
npx ruflo memory retrieve --query "encoding"
npx ruflo hive-mind status
npx ruflo swarm status
npx ruflo mcp status
npx ruflo mcp health
```
But not all MCP tools have CLI counterparts. `claims_board`, `analyze_diff-risk`, `hive-mind_memory` — only via MCP (i.e., via Claude).

**Method 3: Via the MCP Inspector (debugging and administration)**

A web interface for directly invoking any MCP tool with parameters:
```bash
npx @modelcontextprotocol/inspector npx ruflo@latest mcp start
```
Opens the browser → you select a tool → fill in parameters → invoke. Useful for a server administrator when debugging and populating the knowledge base.

---

### Real-world scenarios

**1. Knowledge transfer**

Developer A solved a complex problem → saved the pattern → developer B a week later runs into a similar one → `memory_search` finds the solution.

Prompts for Claude Code:
```
# Save the solution
> Save to ruflo in namespace shared: with parallel workers on a single queue,
> a deadlock occurs, the solution is to add --tries=3 and a unique job ID. Tags: queue, deadlock

# Find the solution
> Search ruflo: workers blocking each other
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Developer A: saves the solution
memory_store(
  key: "fix-deadlock-queue-workers",
  value: "With parallel workers on a single queue, a deadlock occurs.
          Solution: add --tries=3 and a unique job ID.
          See commit abc123.",
  namespace: "shared",
  tags: ["queue", "deadlock", "workers"]
)

# Developer B: a week later searches for a solution to a similar problem
memory_search(
  query: "workers blocking each other",
  namespace: "shared"
)
# → finds the fix-deadlock-queue-workers entry by semantic similarity
```

</details>

**2. Code review**

Risk assessment and reviewer selection based on git history.

Prompts for Claude Code:
```
# Full analysis
> Analyze via ruflo the risks of my diff relative to main,
> pick reviewers, and classify the type of change

# Assess a specific file
> Assess via ruflo the risk of changes in app/Services/PaymentService.php
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Assess the risks of the current diff
analyze_diff-risk(ref: "main..feature-branch")
# → returns: risk score, affected modules, type of changes

# Who to invite for review (based on history of edits to the affected files)
analyze_diff-reviewers(ref: "main..feature-branch", limit: 3)
# → returns: list of developers who most often edited these files

# Classify the change (feature / bug fix / refactoring)
analyze_diff-classify(ref: "main..feature-branch")

# Risk of a specific file
analyze_file-risk(path: "app/Services/PaymentService.php", additions: 50, deletions: 20)
```

</details>

**3. Onboarding**

A new employee connects Claude Code to the server → gets up-to-date knowledge.

Prompts for Claude Code:
```
# Populating the knowledge base (the tech lead does this)
> Save to ruflo namespace onboarding the deployment instructions:
> git push origin main → CI tests → sail artisan migrate → sail npm run build.
> Rollback: git revert + migrate:rollback. Tags: deploy, ci

> Save to ruflo namespace onboarding the local installation instructions:
> git clone, cp .env.example .env, sail up -d, sail artisan migrate,
> sail npm run dev. Tags: setup, docker

# Search by the new employee
> How do I deploy the project locally? Search ruflo in onboarding
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Admin: populates the onboarding namespace ahead of time
memory_store(
  key: "deploy-guide",
  value: "Deploy: git push origin main → CI runs tests →
          sail artisan migrate → sail npm run build.
          Rollback: git revert + sail artisan migrate:rollback.",
  namespace: "onboarding",
  tags: ["deploy", "ci"]
)

memory_store(
  key: "local-setup",
  value: "1. git clone ... 2. cp .env.example .env
          3. sail up -d 4. sail artisan migrate
          5. sail npm run dev — Vite on port 5176",
  namespace: "onboarding",
  tags: ["setup", "docker"]
)

# New employee: looks up how to bring up the project
memory_search(query: "how to deploy the project locally", namespace: "onboarding")
# → finds local-setup

memory_search(query: "how to deploy to prod", namespace: "onboarding")
# → finds deploy-guide
```

</details>

**4. Task coordination**

Several developers work in parallel → claims prevents duplicate work.

Prompts for Claude Code:
```
# Take a task
> Claim task PROJ-42 in ruflo for me (Alexey),
> I'm going to refactor PaymentService

# What's currently in progress
> Show all active tasks in ruflo

# Hand off a task
> Hand off task PROJ-42 in ruflo from me (Alexey) to Boris,
> 60% done, switching to a hotfix

# Task board
> Show the ruflo task board
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Developer A: takes the task
claims_claim(
  issueId: "PROJ-42",
  claimant: "human:dev-a:Alexey",
  context: "Refactoring PaymentService — extracting it into a separate module"
)

# Developer B: sees that the task is taken
claims_list(status: "active")
# → PROJ-42: claimed by human:dev-a:Alexey

# Developer A: hands off the task (got sick / switched)
claims_handoff(
  issueId: "PROJ-42",
  from: "human:dev-a:Alexey",
  to: "human:dev-b:Boris",
  reason: "Switching to a hotfix, module is 60% done",
  progress: 60
)

# Developer B: accepts
claims_claim(
  issueId: "PROJ-42",
  claimant: "human:dev-b:Boris",
  context: "Continuing the refactor from 60%"
)

# View the board of all tasks
claims_board()
```

</details>

**4b. A task between Claude Code sessions (via stealable)**

Scenario: create a task in one project, execute it in another. Both projects are connected to the same ruflo-personal.

Prompts for Claude Code:
```
# Session A (project Alpha): create and release the task
> Claim the task update-ruflo-notion-wiki in ruflo-personal for me (Ivan):
> update an article in Notion WIKI — removed English prompts, added
> a Tasks vs Claims section. Mark as stealable — I'll execute it in another session

# Session B (another project): find and take the task
> Show the free tasks in ruflo-personal

# Session B: take and execute
> Take the task update-ruflo-notion-wiki and execute it
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Session A: create the task (claim creates the record on the first call)
claims_claim(
  issueId: "update-ruflo-notion-wiki",
  claimant: "human:ivan:Ivan",
  context: "Update an article in Notion WIKI about ruflo. Edits: removed English
            prompts, added a Tasks vs Claims section. Notion instructions are
            in ruflo-personal memory."
)

# Session A: mark as free for another session
claims_mark-stealable(
  issueId: "update-ruflo-notion-wiki",
  reason: "voluntary",
  context: "Execute in a session with access to Notion"
)

# Session B: look at free tasks
claims_stealable()
# → update-ruflo-notion-wiki: stealable (voluntary), context of the edits inside

# Session B: take the task
claims_steal(
  issueId: "update-ruflo-notion-wiki",
  stealer: "human:ivan:Ivan"
)
# → status: active, can be executed

# Session B: after execution — complete
claims_status(
  issueId: "update-ruflo-notion-wiki",
  status: "completed",
  note: "Notion WIKI updated"
)
```

</details>

**4c. Team task board (via ruflo-hub)**

Scenario: the team is connected to a shared ruflo-hub (HTTP). The tech lead creates a task, a developer takes it. Everyone sees the same board.

Prompts for Claude Code:
```
# Tech lead: create a task and mark it as free
> Claim task FIX-auth-redirect in ruflo-team for me (Lena):
> after login the redirect to /dashboard doesn't work, cookies aren't being forwarded.
> Mark as stealable

# Developer: look at free tasks
> Show the free tasks in ruflo-team

# Developer: take the task
> Take task FIX-auth-redirect in ruflo-team for me (Alexey)

# Developer: update progress
> Update the status of FIX-auth-redirect in ruflo-team — progress 70%,
> found the cause: SameSite=Strict on the cookie

# Developer: complete
> Complete task FIX-auth-redirect in ruflo-team — fixed, PR #87
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Tech lead: creates the task and immediately releases it
claims_claim(
  issueId: "FIX-auth-redirect",
  claimant: "human:lena:Lena",
  context: "After login the redirect to /dashboard doesn't work,
            cookies aren't being forwarded through middleware"
)
claims_mark-stealable(
  issueId: "FIX-auth-redirect",
  reason: "voluntary",
  context: "Need someone from the backend team"
)

# Developer: sees free tasks
claims_stealable()
# → FIX-auth-redirect: stealable, context about cookies inside

# Developer: takes it
claims_steal(
  issueId: "FIX-auth-redirect",
  stealer: "human:alexey:Alexey"
)

# Developer: updates progress
claims_status(
  issueId: "FIX-auth-redirect",
  status: "active",
  progress: 70,
  note: "Cause: SameSite=Strict on the cookie"
)

# Developer: completes
claims_status(
  issueId: "FIX-auth-redirect",
  status: "completed",
  note: "Fixed, PR #87"
)
```

</details>

**5. Shared context via Hive-Mind**

Shared memory for coordinating parallel work.

Prompts for Claude Code:
```
# Record the plan
> Record in ruflo hive-mind the auth refactoring plan: extract into a separate package,
> do NOT touch middleware until Tuesday, API contract: POST /api/auth/login,
> POST /api/auth/refresh

# Read the plan
> What's in ruflo hive-mind about the auth refactor?

# Notification
> Broadcast via ruflo hive-mind to everyone: merge freeze until 5:00 PM, release deploy.
> High priority

# List everything in shared memory
> Show everything in ruflo hive-mind memory
```

<details>
<summary>Tool invocations (what Claude will execute)</summary>

```bash
# Lead: records the refactoring context
hive-mind_memory(
  action: "set",
  key: "refactor-auth-plan",
  value: "Extract auth into a separate package. Do NOT touch middleware until Tuesday.
          API contract: POST /api/auth/login, POST /api/auth/refresh."
)

# Any developer: reads the context
hive-mind_memory(action: "get", key: "refactor-auth-plan")

# Notify all agents
hive-mind_broadcast(
  message: "Merge freeze until 5:00 PM, release deploy",
  priority: "high"
)

# View all keys of shared memory
hive-mind_memory(action: "list")
```

</details>

### Remote agent launching

**Can I launch an agent on another machine from my workstation?**

No. Ruflo-server coordinates knowledge and tasks, but does not manage Claude Code on other people's machines.

```
Alexey's machine              Ruflo Server                Boris's machine
┌────────────────┐            ┌────────────────┐          ┌────────────────┐
│ Claude Code    │─MCP request─│ Memory        │─MCP request─│ Claude Code    │
│ (its own proc) │            │ Tasks          │          │ (its own proc) │
│ reads/writes   │            │ Coordination   │          │ reads/writes   │
│ ITS OWN files  │            │                │          │ ITS OWN files  │
└────────────────┘            └────────────────┘          └────────────────┘
```

- `agent_spawn` creates an agent **inside** the ruflo server or the current Claude Code session — not on another machine
- `claims_handoff` passes task **metadata** — Boris has to start Claude Code himself and pick it up
- `hive-mind_broadcast` sends a message **to agents within a single swarm** — not to another developer's Claude Code

**What works:**

| Scenario | Possible? | How |
|----------|-----------|-----|
| Assign a task to another developer | Yes | `claims_claim` / `claims_handoff` |
| Send a message to all agents | Yes | `hive-mind_broadcast` |
| Shared memory between everyone | Yes | `memory_store` / `hive-mind_memory` |
| Run code on another machine | No | — |
| Run an agent on a shared server | Possible | Headless Claude Code on the server |
| Run an agent in CI | Yes | Via webhook → GitHub Actions |
| Ruflo workers | Yes, but locally | Background analytical tasks inside ruflo |

**Options for remote task execution:**

**Option A: Headless Claude Code on a shared server**

```
Shared server
├── Ruflo MCP Server
├── Claude Code (headless, daemon)  ← executes tasks
├── Git repositories (clones)
└── Code is available locally

Developer → assigns a task → server executes it
```

All agents run on a single machine with the code. Developers submit tasks to the server rather than launching something on each other's machines.

**Option B: CI/CD pipeline as the executor**

```
Developer → creates a task in ruflo → webhook → GitHub Actions / CI →
→ runs Claude Code in a container → result back into ruflo
```

### Ruflo Background Workers (not to be confused with remote launching)

Ruflo has **12 built-in background workers** — these are local analytical tasks inside the ruflo process, not a mechanism for remotely launching Claude Code on another machine.

```bash
# CLI
npx ruflo worker dispatch --trigger audit --context "./src"
npx ruflo worker status

# Prompts for Claude Code
> Run a ruflo security audit for ./app/Servlets/
```

| Trigger | What it does | Time |
|---------|-----------|-------|
| `ultralearn` | Deep study and synthesis of knowledge | ~60s |
| `optimize` | Profiling and optimization | ~30s |
| `consolidate` | Memory cleanup and deduplication | ~20s |
| `predict` | Predictive preload and caching | ~15s |
| `audit` | Vulnerability scanning | ~45s |
| `map` | Mapping codebase architecture | ~30s |
| `preload` | Warming up the cache | ~10s |
| `deepdive` | Deep code analysis | ~60s |
| `document` | Autogenerating documentation | ~45s |
| `refactor` | Refactoring suggestions | ~30s |
| `benchmark` | Performance benchmarks | ~60s |
| `testgaps` | Test coverage analysis | ~30s |

Workers run **inside the ruflo process** — they are not LLM calls and not Claude Code sessions. Useful for automating routine checks, but do not replace remote launching of agents.

### What to consider when deploying

| Risk | Mitigation |
|------|-----------|
| Secrets in memory | Call `aidefence_has_pii` before `memory_store` to check for PII (email, keys, tokens). There is no automatic protection — this is a manual check. Namespace does not restrict access, any client can read any namespace |
| Network latency | Embedding generation (ONNX) happens on the server. For remote workers — VPN |
| Database size | temporal decay (30 days), TTL, periodic `memory_stats` and `memory cleanup` |
| Administration | Designate someone responsible for the namespace structure and cleanup of stale patterns |
| Backups | `npx ruflo ruvector backup --output ./backup.sql` or standard `pg_dump`. There is no built-in scheduler — set up via cron |

## stdio mode limitations (IMPORTANT)

> **Critical limitation:** In stdio mode, each **project** gets its own ruflo process. More than half of ruflo's functionality stores state **in the process's memory** and is not shared between projects.
>
> **Nuance:** Within a single project, Claude Code **reuses** one ruflo process for all sessions (`claude /new`, a new terminal). So claims, tasks, and hive-mind **are visible** between sessions of one project, but **not visible** from another project. (Verified experimentally, 2026-04-16.)

### What is shared (SQLite → `.swarm/memory.db`)

| Subsystem | Tools |
|---|---|
| Memory | `memory_store`, `memory_search`, `memory_search_unified` |
| Patterns | `hooks_intelligence_pattern-store`, `hooks_intelligence_pattern-search` |
| Trajectories | `hooks_intelligence_trajectory-*` |
| Sessions | `session_save`, `session_restore` |
| Embeddings | `embeddings_generate`, `embeddings_search` |

Sharing works thanks to a wrapper with a fixed `cwd` → a single file `~/.ruflo-personal/.swarm/memory.db` (see the section "Personal ruflo: shared memory between projects").

### What is NOT shared between projects (in-memory → tied to the process)

| Subsystem | Tools | What is lost |
|---|---|---|
| **Claims** | `claims_claim`, `claims_board`, `claims_handoff`... | Task board, claims, handoffs |
| **Tasks** | `task_create`, `task_assign`, `task_list`... | Task tracker and assignments |
| **Hive-Mind** | `hive-mind_init`, `hive-mind_broadcast`, `hive-mind_memory`... | Shared swarm memory, notifications |
| **Agents** | `agent_spawn`, `agent_pool`, `agent_list`... | Running agents and their state |
| **Coordination** | `coordination_sync`, `coordination_consensus`... | Topology, load balancing |
| **Swarm** | `swarm_init`, `swarm_status`... | Swarm and its configuration |
| **Workflows** | `workflow_create`, `workflow_execute`... | Templates and execution state |
| **Autopilot** | `autopilot_enable`, `autopilot_predict`... | Prediction model |
| **Neural** | `neural_train`, `neural_predict`... | Trained models |

### Summary: what is visible where

| Subsystem | Sessions of one project | Between projects (stdio) | ruflo-hub |
|---|---|---|---|
| Memory, patterns, embeddings | ✓ (shared `.swarm/`) | ✓ (shared `.swarm/`) | ✓ |
| Claims, tasks, hive-mind | ✓ (shared process) | **✗** (different processes) | ✓ |
| Agents, coordination, swarm | ✓ (shared process) | **✗** | ✓ |
| Process restart (`/mcp`) | In-memory is lost | In-memory is lost | In-memory is lost |

### Solution for multi-project work: ruflo-hub

For claims, tasks, and hive-mind to work **between projects**, you need **a single continuously running ruflo process** wrapped in HTTP. The ready-made solution is [ruflo-hub](https://github.com/jazz-max/ruflo-hub):

```bash
git clone https://github.com/jazz-max/ruflo-hub.git
cd ruflo-hub && cp .env.example .env
docker compose up -d
```

```
Project A ──HTTP──┐
Project B ──HTTP──┤── ruflo-hub (single process) ── .swarm/memory.db
Project C ──HTTP──┘        ↑
                    all in-memory state
                    lives in one process
                    and is visible to all projects
```

### Workaround: tasks via memory

Without ruflo-hub, to pass tasks between projects you can use `memory_store` / `memory_search` with the namespace `tasks` — they write into a shared `memory.db` and are visible from anywhere.

```
# Project A: create a task
> Save in ruflo-personal namespace tasks the key fix-auth-redirect:
> Status: open. Fix the redirect after login. Tags: bug, auth, open

# Project B: find tasks
> Show entries in ruflo-personal namespace tasks

# Project B: close the task (upsert)
> Update in ruflo-personal the key fix-auth-redirect in namespace tasks:
> Status: done, completed 2026-04-16
```

## Personal ruflo: shared memory between projects (stdio)

### Problem

When setting up `ruflo-personal` as an stdio MCP at the user level (`~/.claude.json`):

```json
"ruflo-personal": {
  "type": "stdio",
  "command": "npx",
  "args": ["ruflo@latest", "mcp", "start"]
}
```

Each Claude Code launches **its own** ruflo process with the `cwd` of the current project. The memory bridge (`@claude-flow/cli/dist/src/memory/memory-bridge.js`) hard-codes the use of `process.cwd()`:

```js
function getDbPath(customPath) {
    const swarmDir = path.resolve(process.cwd(), '.swarm');
    if (!customPath)
        return path.join(swarmDir, 'memory.db');
    // Path traversal protection — a path outside cwd is ignored
    const cwd = process.cwd();
    if (!resolved.startsWith(cwd)) {
        return path.join(swarmDir, 'memory.db'); // fallback
    }
}
```

**Result:** from project Alpha you save 198 records, from project Beta — 0. Different `.swarm/memory.db` in each project.

### Why env variables don't help

`CLAUDE_FLOW_MEMORY_PATH` and `CLAUDE_FLOW_DATA_DIR` are documented in the ruflo README, but **memory-bridge does not read them**. They are used only in documentation templates (`claudemd-generator.js`) and in the description of the memory-specialist agent, but not in the actual MCP server code.

### Solution: a wrapper with a fixed cwd

Create a wrapper script that does `cd` into a shared folder before starting ruflo:

**1. Create the folder and script:**

```bash
mkdir -p ~/.ruflo-personal

cat > ~/.ruflo-personal/start.sh << 'EOF'
#!/bin/bash
cd ~/.ruflo-personal
exec npx ruflo@latest mcp start
EOF

chmod +x ~/.ruflo-personal/start.sh
```

**2. Update `~/.claude.json`:**

```json
"ruflo-personal": {
  "type": "stdio",
  "command": "bash",
  "args": ["/Users/<username>/.ruflo-personal/start.sh"],
  "env": {}
}
```

> **Important:** `args` needs an **absolute path** (`/Users/<username>/...`), not `~/.ruflo-personal/...`. The tilde `~` is a shell expansion, it is expanded only when the shell parses the command line. Claude Code launches MCP servers via `spawn()`, passing arguments directly to the process without shell processing. Bash will receive the literal string `~/.ruflo-personal/start.sh` and will not find such a file.

**3. Migrate existing data (if any):**

```bash
# Copy .swarm from the project where records already existed
cp -r /path/to/project/.swarm ~/.ruflo-personal/
```

Now **all** Claude Code sessions (from any project) will use the single database `~/.ruflo-personal/.swarm/memory.db`.

### Alternatives

| Option | Pros | Cons |
|---------|-------|--------|
| **Wrapper with cd** (recommended) | One change in ~/.claude.json, doesn't touch projects | None |
| **Symlink .swarm/** in each project | Works without changing the config | Need to add the symlink in each new project |
| **SSE server** from a fixed directory | The most "proper" one | Requires a continuously running process |

## Hybrid scheme: personal ruflo + team servers

Typical situation: a single developer participates in several projects with different teams, plus has personal projects. The solution is several ruflo instances with different scopes.

### Architecture

```
┌───────────────────────────────────────────────────────┐
│  Team server A (project Alpha)                        │
│  ruflo-hub --port 3001                                │
│  Users: you + the Alpha project team                  │
└──────────────────────────┬────────────────────────────┘
                           │
┌──────────────────────────┼────────────────────────────┐
│  Team server B (project Beta)                         │
│  ruflo-hub --port 3002                                │
│  Users: you + the Beta project team                   │
└──────────────────────────┼────────────────────────────┘
                           │
┌──────────────────────────┼────────────────────────────┐
│  Personal ruflo (stdio or ruflo-hub)                  │
│  Memory import from all projects                      │
│  Only for you, available in any project               │
│  stdio: memory is shared, claims — not                │
│  ruflo-hub: everything is shared between projects     │
└──────────────────────────┴────────────────────────────┘
```

### Claude Code configuration

**1. Personal ruflo — globally** (user scope):

Available in all projects, accumulates personal experience.

**Option A: stdio (simple, memory is shared, claims — not)**

```bash
# Add (with a wrapper for the shared database, see the "Personal ruflo: shared memory" section)
claude mcp add ruflo-personal -s user -- bash /Users/<username>/.ruflo-personal/start.sh

# Check
claude mcp get ruflo-personal

# Remove
claude mcp remove ruflo-personal -s user
```

**Option B: ruflo-hub (everything is shared between projects)**

```bash
# Bring up a personal ruflo-hub (Docker)
git clone https://github.com/jazz-max/ruflo-hub.git ~/ruflo-personal-server
cd ~/ruflo-personal-server && cp .env.example .env
docker compose up -d

# Add to Claude Code
claude mcp add ruflo-personal -s user --transport http --url http://localhost:3000/mcp

# Or via ~/.claude.json:
# "ruflo-personal": {
#   "type": "http",
#   "url": "http://localhost:3000/mcp"
# }
```

> In Option B, claims, tasks, and hive-mind work between all projects and sessions. The downside is that a running Docker container is required.

**2. Team ruflo — at the project level** (project scope):

Committed into git — each team member automatically gets access.

```bash
# In the Alpha project directory
claude mcp add ruflo-team -s project --transport http --url http://server-alpha:3001/mcp

# In the Beta project directory
claude mcp add ruflo-team -s project --transport http --url http://server-beta:3002/mcp
```

> The name `ruflo-team` is the same in both projects — for the developer the interface is uniform, while the URL differs.

### What Claude Code sees in each project

| Context | MCP servers | Source of settings |
|----------|-------------|-------------------|
| Project Alpha | `ruflo-personal` + `ruflo-team` (→ server-alpha) | global + project |
| Project Beta | `ruflo-personal` + `ruflo-team` (→ server-beta) | global + project |
| Personal project | `ruflo-personal` | only global |

### Prompts in the context of multiple ruflos

```
# In project Alpha — Claude sees both servers
> Save to ruflo-team: solution to the encoding problem...

> Search ruflo-personal: how did we solve encoding in other projects?

# In project Beta — Claude sees a different pair
> Save to ruflo-team: nginx config for proxying...

> Search ruflo-personal: were there similar nginx settings?

# In the personal project — only personal
> Search ruflo-personal: authorization patterns across all projects
```

### Initial seeding of personal ruflo

```
# Import memory from all Claude Code projects
> Import memory from all projects into ruflo-personal

# Claude will execute:
memory_import_claude(allProjects: true)
# → all memory files → embeddings → semantic search across all projects
```

Personal ruflo becomes a **bridge between projects** — experience from all of them flows into it, while team ruflos are isolated from each other.

### Knowledge flows

```
Project Alpha ──→ ruflo-team-alpha ──→ Alpha team
     │
     └──→ ruflo-personal ←──────┐
                                │
Project Beta  ──→ ruflo-team-beta ──→ Beta team
     │                          │
     └──→ ruflo-personal ←──────┘
                  │
Personal projects─┘

ruflo-personal = your personal "brain" with knowledge from all projects
ruflo-team-*   = team memory, isolated per project
```

## Recommended approach

### For a single developer

1. **Ruflo via a wrapper** (stdio + fixed cwd) in `~/.claude.json` — a shared database for all projects (see the "Personal ruflo: shared memory between projects" section)
2. **`memory_import_claude(allProjects: true)`** — combine memory from all projects
3. **Namespace per project** — `project:{name}` for organization

### For a team (one project)

1. **Ruflo MCP server** with HTTP transport on a dedicated machine with PostgreSQL (RuVector)
2. **`.claude/settings.json` in the repository** — all team members are automatically connected
3. **`CLAUDE.md`** — source of truth for project rules (shared via git)
4. **Namespace convention** — `dev:`, `project:`, `team:`, `shared`

### For multiple teams and projects

1. **Personal ruflo** globally — a bridge between projects, accumulating experience
2. **Team ruflo** in each project — isolated team memory
3. **A single name** `ruflo-team` in the projects' `.claude/settings.json` — a uniform interface
4. **Git** — the primary way to exchange code and documentation

Ruflo amplifies individual productivity and provides team memory, while code and documentation live in git.
