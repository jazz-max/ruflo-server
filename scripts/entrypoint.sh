#!/bin/bash
set -e

echo "=== Ruflo MCP Server ==="
echo "Port: ${RUFLO_PORT}"
echo "PostgreSQL: ${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

# Export PG* variables so all tools (psql, ruflo ruvector) use the correct host
export PGHOST="${POSTGRES_HOST}"
export PGPORT="${POSTGRES_PORT}"
export PGDATABASE="${POSTGRES_DB}"
export PGUSER="${POSTGRES_USER}"
export PGPASSWORD="${POSTGRES_PASSWORD}"

# Wait for PostgreSQL — but don't block if PG is disabled (lean mode)
# Short probe first: if PG is not reachable within 5s, skip and run PG-less.
echo "Probing PostgreSQL..."
if pg_isready -q -t 5 2>/dev/null; then
  echo "PostgreSQL is ready."

  # Initialize RuVector schema if not already done
  TABLE_EXISTS=$(psql -tAc \
    "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'claude_flow');" 2>/dev/null || echo "false")

  if [ "${TABLE_EXISTS}" = "f" ] || [ "${TABLE_EXISTS}" = "false" ]; then
    echo "Initializing RuVector schema..."
    ruflo ruvector init \
      --database "${POSTGRES_DB}" \
      --user "${POSTGRES_USER}" \
      --host "${POSTGRES_HOST}" \
      --port "${POSTGRES_PORT}" \
      || echo "RuVector init skipped (may need manual setup)"
  else
    echo "RuVector schema already exists."
  fi
else
  echo "PostgreSQL not reachable at ${POSTGRES_HOST}:${POSTGRES_PORT} — running in lean mode (sql.js only)."
  echo "Enable PG: set COMPOSE_PROFILES=pg in .env or run 'docker compose --profile pg up'"
fi

# Health-check stubs: create marker files at the paths system_health probes,
# so other Claude instances stop suggesting `ruflo init` / `memory init`.
# The real backend lives in /app/.swarm/memory.db (volume); these files are formal only.
#
# CAUTION: If `store.json` exists but `.migrated-to-sqlite` does NOT, ruflo's
# memory_store handler treats store.json as a legacy JSON dump and tries to
# migrate it on every call. A `{}` payload makes that migration crash with
# "Cannot convert undefined or null to object" because `legacyStore.entries`
# is undefined. We always write the migration marker alongside store.json
# to short-circuit that code path.
mkdir -p /app/.claude-flow/memory
[ -f /app/.claude-flow/memory/store.json ] || echo '{}' > /app/.claude-flow/memory/store.json
[ -f /app/.claude-flow/memory/.migrated-to-sqlite ] || echo "{\"migratedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"version\":\"3.0.0\"}" > /app/.claude-flow/memory/.migrated-to-sqlite
[ -f /app/.claude-flow/config.json ] || echo '{}' > /app/.claude-flow/config.json

# MCP proxy: Express + Streamable HTTP wrapping ruflo stdio
echo "Starting Ruflo MCP proxy on port ${RUFLO_PORT}..."
exec node /app/server.mjs
