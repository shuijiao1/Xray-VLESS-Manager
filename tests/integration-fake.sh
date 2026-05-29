#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=${TMPDIR:-/tmp}/xray-vless-manager-test-$$
mkdir -p "$TMP/bin" "$TMP/xray"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/bin/xray" <<'XRAY'
#!/usr/bin/env bash
case "${1:-}" in
  uuid) echo "11111111-1111-4111-8111-111111111111" ;;
  x25519)
    echo "Private key: priv_test_key"
    echo "Public key: pub_test_key"
    ;;
  help)
    [[ "${2:-}" == "vlessenc" ]] && exit 0
    exit 0
    ;;
  vlessenc)
    echo "mlkem768x25519plus.native.600s.100-111-1111.75-0-111.50-0-3333.test_auth_key"
    ;;
  test)
    config=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "-config" ]] && { config=$2; shift 2; continue; }
      shift
    done
    jq empty "$config"
    echo "Configuration OK."
    ;;
  run) exit 0 ;;
  *) echo "fake xray: $*" ;;
esac
XRAY
chmod +x "$TMP/bin/xray"

cat > "$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "$*" in
  *"is-active"*) exit 1 ;;
  *) echo "fake systemctl $*" >/dev/null; exit 0 ;;
esac
SYSTEMCTL
chmod +x "$TMP/bin/systemctl"

cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
case "$*" in
  *api.ipify.org*|*ifconfig.me*) echo "203.0.113.10" ;;
  *) echo "fake curl called for $*"; exit 1 ;;
esac
CURL
chmod +x "$TMP/bin/curl"

run_case() {
  local name=$1 input=$2 expect=$3
  local dir="$TMP/$name"
  mkdir -p "$dir/etc"
  printf '%b' "$input" | env \
    PATH="$TMP/bin:$PATH" \
    TERM=xterm \
    XRAY_DIR="$dir/xray" \
    XRAY_BIN="$TMP/bin/xray" \
    XRAY_SERVICE="$dir/xray.service" \
    bash ./xray-vless.sh >"/tmp/${name}.out"
  jq empty "$dir/xray/config.json"
  jq empty "$dir/xray/client.json"
  grep -q "$expect" "$dir/xray/client.txt"
}

run_case tcp '2\n8443\n\n0\n' 'VLESS TCP'
run_case vision_reality '3\n8443\nwww.microsoft.com\n\n0\n' 'XTLS Vision + REALITY'
run_case tcp_reality '4\n8443\nwww.microsoft.com\n\n0\n' 'TCP + REALITY'
run_case ws_tls '5\n8443\nexample.com\n/ws-test\n\n0\n' 'WebSocket + TLS'
run_case grpc_reality '6\n8443\nwww.microsoft.com\n\n0\n' 'gRPC + REALITY'
run_case xhttp_reality '7\n8443\nwww.microsoft.com\n/xhttp-test\n\n0\n' 'XHTTP + REALITY'
run_case vlessenc '8\n8443\n\n0\n' 'VLESS Encryption'

# Existing config without client.txt should be recoverable from menu 9.
recover_dir="$TMP/recover_existing"
mkdir -p "$recover_dir/xray"
cat > "$recover_dir/xray/config.json" <<'JSON'
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 53589,
    "protocol": "vless",
    "settings": { "clients": [{ "id": "22222222-2222-4222-8222-222222222222" }], "decryption": "none" },
    "streamSettings": { "network": "tcp", "security": "none" }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
printf '9\n\n0\n' | env \
  PATH="$TMP/bin:$PATH" \
  TERM=xterm \
  XRAY_DIR="$recover_dir/xray" \
  XRAY_BIN="$TMP/bin/xray" \
  XRAY_SERVICE="$recover_dir/xray.service" \
  bash ./xray-vless.sh >/tmp/recover_existing.out
jq empty "$recover_dir/xray/client.json"
grep -q '22222222-2222-4222-8222-222222222222' "$recover_dir/xray/client.txt"
grep -q 'vnext' "$recover_dir/xray/client.json"

echo "fake integration tests passed"
