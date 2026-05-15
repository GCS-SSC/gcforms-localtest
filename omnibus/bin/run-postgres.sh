#!/usr/bin/env bash
set -euo pipefail

POSTGRES_DATA="${POSTGRES_DATA:-/data/postgres}"
POSTGRES_BINDIR="$(pg_config --bindir)"

exec gosu postgres "${POSTGRES_BINDIR}/postgres" \
  -D "$POSTGRES_DATA" \
  -c listen_addresses='*' \
  -c port=5432
