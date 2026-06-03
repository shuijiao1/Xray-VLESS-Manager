#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n xray-vless.sh
needles=(
  'VLESS-TCP-XTLS-Vision-REALITY'
  'VLESS-TCP-REALITY'
  'VLESS-gRPC-REALITY'
  'VLESS-XHTTP-Reality'
  'vlessenc'
  'x25519'
  'run -test -config'
)
for n in "${needles[@]}"; do
  grep -q "$n" xray-vless.sh README.md README.en.md 2>/dev/null || grep -q "$n" xray-vless.sh
 done
