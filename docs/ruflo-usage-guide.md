# Ruflo — practical usage guide

A distilled version of the official README from [ruvnet/ruflo](https://github.com/ruvnet/ruflo), marketing aside. What you actually need to know and do.

---

## What ruflo actually is

An orchestrator for Claude Code with 4 core functions:

1. **Hooks** — automatically pick the model/agent for a task, record patterns, trigger background processes
2. **Memory** — vector DB (HNSW) for patterns, 3 scope levels (project / local / user)
3. **Swarm** — coordination of multiple agents on one task (hierarchical/mesh/ring/star)
4. **Skills** — 130+ ready-made scenarios (`sparc:coder`, `github-code-review`, etc.)

The main idea straight from their docs:

> **After `init` just work in Claude Code as usual — hooks route tasks on their own, learn from successes, and coordinate work in the background. The 310+ MCP tools are only needed for fine-grained control.**

---

## Everyday commands (what actually gets used)

```bash
# One-time — project initialization
npx ruflo@latest init           # creates .claude/, .claude-flow/, hooks, etc.

# Upgrade without losing data
npx ruflo@latest init upgrade

# Adding new skills/agents
npx ruflo@latest init upgrade --add-missing

# Verify the install
npx ruflo@latest mcp list       # what's available
node .claude/helpers/hook-handler.cjs stats   # learning stats
```

Everything else is done through **MCP inside Claude Code**, without the CLI.

To connect to a centralized `ruflo-hub` instead of a local install, use the `/setup` script from [ruflo-hub](https://github.com/jazz-max/ruflo-hub) — it configures hooks + memory bridge + MCP in a single `curl | bash`.

---

## Self-learning loop (Intelligence Loop)

The key ruflo pattern (ADR-050), which runs automatically via hooks:

```
1. RETRIEVE    memory_search("similar tasks")                ← before starting
2. JUDGE       evaluate what worked / what didn't
3. DISTILL     memory_store("...", namespace="patterns")    ← after success
4. CONSOLIDATE background pattern aggregation (EWC++)
5. ROUTE       Q-learning picks the agent/model next time
```

You don't do anything by hand — the `post-edit` and `post-task` hooks trigger this themselves.

---

## 5 MCP tools actually worth knowing

Out of ruflo's 313 tools, **these cover 90% of cases**:

| Tool | When to call | Why |
|------|----------------|-------|
| `memory_search` | **Before** a complex task | Find ready-made team patterns |
| `memory_store` | **After** a successful solution | Save into `namespace="patterns"` or `"shared"` |
| `swarm_init` | When a task splits into 3+ independent tracks | Coordination + anti-drift |
| `agent_spawn` | Paired with `swarm_init` | Register roles (coder, tester, reviewer) |
| `hooks_route` | Not sure which model to pick | Q-learning decides for you |

---

## When a swarm is actually needed

Per their own documentation — **only for complex tasks with explicit parallelism**. Recommended anti-drift configuration:

```javascript
swarm_init({
  topology: "hierarchical",   // queen → workers, prevents "drift"
  maxAgents: 8,               // no more, or focus is lost
  strategy: "specialized"     // clear roles, no overlap
})
```

### Task → Agent Routing (their table)

| Code | Task type | Agents |
|-----|-----------|--------|
| 1 | Bug fix | coordinator, researcher, coder, tester |
| 3 | Feature | coordinator, architect, coder, tester, reviewer |
| 5 | Refactor | coordinator, architect, coder, reviewer |
| 7 | Performance | coordinator, perf-engineer, coder |
| 9 | Security | coordinator, security-architect, auditor |
| 11 | Memory | coordinator, memory-specialist, perf-engineer |

For simple tasks (a one-off bug fix, small tweaks) — **not needed**. Claude Code handles it on its own via the Task tool.

More on the swarm/agent concept as "records in a DB, not processes" — see [`swarm-management.md`](./swarm-management.md).

---

## Skills — what many people miss

Skills = scenarios that Claude Code loads on command. Ruflo ships 130+:

```
$sparc:architect              → SPARC Architect Mode
$sparc:coder                  → SPARC Coder Mode
$github-code-review           → PR review swarm
$swarm-orchestration          → swarm patterns
$reasoningbank-intelligence   → learning patterns
$pair-programming             → driver/navigator
```

Invoked via a normal request: *"use the sparc:architect skill to design X"*.

### Popular categories

| Category | Examples |
|-----------|---------|
| **SPARC** | `sparc:architect`, `sparc:coder`, `sparc:tester`, `sparc:debugger` |
| **V3 Core** | `v3-security-overhaul`, `v3-memory-unification`, `v3-performance-optimization` |
| **AgentDB** | `agentdb-vector-search`, `agentdb-optimization`, `agentdb-learning` |
| **Swarm** | `swarm-orchestration`, `swarm-advanced` |
| **GitHub** | `github-code-review`, `github-workflow-automation`, `github-multi-repo` |
| **Flow Nexus** | `flow-nexus-neural`, `flow-nexus-swarm`, `flow-nexus-workflow` |

---

## A practical day-to-day workflow

```
1. Morning, first Claude Code session:
   - Hook SessionStart → auto-memory-hook.mjs import
   - Yesterday's team patterns are pulled into context from ruflo-hub

2. Starting the task "add feature X":
   - (me) "search memory for anything similar we've done"
   - Claude: mcp__ruflo__memory_search("similar to X")
   - Claude sees the pattern, adapts it

3. The task is large, five tracks:
   - (me) "use a hierarchical swarm of 6 agents"
   - Claude: swarm_init + 6× agent_spawn with coder/tester/arch/... roles
   - Claude parallelizes work via the Task tool inside its own session

4. The task is complex, want best practices applied:
   - (me) "use the sparc:architect skill"
   - Claude loads the SPARC scenario, designs step by step

5. Task solved:
   - Hook post-task → automatic memory_store of the pattern
   - Stop hook → auto-memory-hook.mjs sync → shares with the team

6. In the evening:
   - No cleanup needed, everything persists in ruflo-hub volumes
```

---

## 3-tier model routing (API cost savings)

Ruflo automatically routes tasks to the optimal handler:

| Tier | Handler | Latency | Cost | Use cases |
|------|---------|-------------|-----------|-------|
| **1** | Agent Booster (WASM) | <1ms | $0 | var→const, add-types, remove-console |
| **2** | Haiku/Sonnet | 500ms-2s | $0.0002-$0.003 | Bug fixes, refactoring, feature implementation |
| **3** | Opus | 2-5s | $0.015 | Architecture, security design, distributed systems |

Routing: Q-learning with epsilon-greedy exploration, sub-millisecond decision latency. 30-50% token savings.

### Signals in hook output

```bash
# Agent Booster available — skip the LLM
[AGENT_BOOSTER_AVAILABLE] Intent: var-to-const
→ Use Edit tool directly, instant (regex-based, no LLM call)

# Model recommendation for the Task tool
[TASK_MODEL_RECOMMENDATION] Use model="haiku"
→ Pass model="haiku" to Task tool for cost savings
```

---

## What's worth remembering from the official docs

- **"After init just talk to Claude normally"** — no need to learn 310 tools. Hooks sort everything out.
- **Agent Booster (WASM)** — simple transformations (var→const, add-types) run **without** an LLM, instantly. Saves $ and time.
- **3-tier routing** — simple things via WASM ($0), medium via Haiku/Sonnet, complex via Opus. Automatically.
- **Skills > raw commands** — instead of "build a swarm with these settings" say "use the $swarm-orchestration skill". A pre-vetted scenario.

---

## Important: most of the "smart" features require configured hooks

Hooks are configured in `.claude/settings.json` — `init` sets them up. If hooks are disabled or unconfigured, only what you invoke manually via MCP will work.

The `/setup` script from [ruflo-hub](https://github.com/jazz-max/ruflo-hub) installs the base hooks + memory bridge + MCP connection in one command:

```bash
curl "http://<hub>:3000/setup?token=TOKEN&name=ruflo" | bash
```

---

## Installing ruflo locally (alternative to ruflo-hub)

If you don't need shared memory and want ruflo as a local tool:

```bash
# Prerequisite
npm install -g @anthropic-ai/claude-code

# Quick init
npx ruflo@latest init --wizard

# Or a one-line full install
curl -fsSL https://cdn.jsdelivr.net/gh/ruvnet/ruflo@main/scripts/install.sh | bash -s -- --full

# MCP integration in Claude Code
claude mcp add ruflo -- npx -y ruflo@latest mcp start
```

### Install profiles

| Profile | Size | Use Case |
|---------|------|----------|
| `--omit=optional` | ~45MB | Core CLI only (fastest) |
| Default | ~340MB | Full install with ML/embeddings |

---

## Summary in one paragraph

Ruflo is **Claude Code on steroids**: you install it via `init`, and it automatically remembers what works, routes tasks to cheaper models when possible, stores the team's collective memory, and gives you 130+ ready-made scenarios. The main value for a team is **shared memory** (find a solution once — the whole team gets it). Swarm and the rest are for a single developer's complex tasks, not for team coordination.

---

## Sources

- [ruvnet/ruflo GitHub](https://github.com/ruvnet/ruflo)
- [ruflo README](https://github.com/ruvnet/ruflo/blob/main/README.md)
- [Ruflo v3.5 Release Overview](https://github.com/ruvnet/ruflo/issues/1240)
- [SitePoint: Deploying Multi-Agent Swarms with Ruflo](https://www.sitepoint.com/deploying-multiagent-swarms-with-ruflo-beyond-singleprompt-coding/)
