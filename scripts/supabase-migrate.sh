#!/usr/bin/env bash
# Applies pending migrations from supabase/migrations to one Supabase database and
# writes to the job summary which files were applied, or which one failed.
#
# Required env: SUPABASE_DB_URL, a Postgres connection string. Connecting directly
# works for both self-hosted Supabase (dev, on Cloudfy) and supabase.com (prod,
# via the Session pooler URL), so no access token or project link is needed.
# The CLI records applied migrations in supabase_migrations.schema_migrations on
# the remote database, so only files not yet in that table are pushed.
set -uo pipefail

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
log="$(mktemp)"
migration_re='[0-9]+_[^[:space:]]+\.sql'

if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "::error::Secret SUPABASE_DB_URL is empty. Register it in this GitHub Environment."
  exit 1
fi

# Dry run first: the log keeps a record of exactly what was about to run.
echo "::group::Pending migrations (dry run)"
supabase db push --db-url "$SUPABASE_DB_URL" --dry-run --yes 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
echo "::endgroup::"
if [ "$status" -ne 0 ]; then
  echo "::error::supabase db push --dry-run failed"
  exit 1
fi
pending=$(grep -oE "$migration_re" "$log" | sort -u)

supabase db push --db-url "$SUPABASE_DB_URL" --yes 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# The CLI prints "Applying migration <file>..." before each file, so on failure
# the last one printed is the one that broke.
started=$(grep -E 'Applying migration' "$log" | grep -oE "$migration_re")

{
  echo "## Supabase migrations"
  echo
  if [ "$status" -eq 0 ]; then
    if [ -z "$started" ]; then
      echo "No pending migrations. Remote database already up to date."
    else
      echo "Applied:"
      echo "$started" | sed 's/^/- `/; s/$/`/'
    fi
  else
    failed=$(echo "$started" | tail -n 1)
    applied=$(echo "$started" | sed '$d')
    echo "**Failed on \`${failed:-unknown (failed before any file ran)}\`**"
    echo
    if [ -n "$applied" ]; then
      echo "Applied before the failure:"
      echo "$applied" | sed 's/^/- `/; s/$/`/'
      echo
    fi
    if [ -n "$pending" ]; then
      echo "Were pending in this run:"
      echo "$pending" | sed 's/^/- `/; s/$/`/'
      echo
    fi
    echo '```'
    tail -n 30 "$log"
    echo '```'
  fi
} >> "$summary"

if [ "$status" -ne 0 ]; then
  echo "::error file=supabase/migrations/${failed:-}::Migration failed: ${failed:-unknown}"
  exit 1
fi
