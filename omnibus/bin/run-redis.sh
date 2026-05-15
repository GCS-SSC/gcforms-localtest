#!/usr/bin/env bash
set -euo pipefail

mkdir -p /data/redis
exec redis-server --dir /data/redis --appendonly yes --protected-mode no --bind 0.0.0.0
