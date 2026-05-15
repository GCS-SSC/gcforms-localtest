#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${GC_FORMS_ROOT:-/opt/gcforms}"
PATH="${ROOT_DIR}/.tools/node-v24.15.0-linux-x64/bin:${PATH}"

cd "${ROOT_DIR}/forms-api"
exec "${ROOT_DIR}/omnibus/bin/wait-bootstrap.sh" corepack pnpm dev
