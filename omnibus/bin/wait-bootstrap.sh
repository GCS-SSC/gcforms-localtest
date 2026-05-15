#!/usr/bin/env bash
set -euo pipefail

for _ in $(seq 1 600); do
  if [[ -f /run/gcforms/bootstrap.done ]]; then
    exec "$@"
  fi
  sleep 1
done

echo "Timed out waiting for GCForms bootstrap" >&2
exit 1
