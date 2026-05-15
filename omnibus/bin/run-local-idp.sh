#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${GC_FORMS_ROOT:-/opt/gcforms}"
PATH="${ROOT_DIR}/.tools/node-v24.15.0-linux-x64/bin:${PATH}"

exec node "${ROOT_DIR}/omnibus/local-idp-server.mjs"
