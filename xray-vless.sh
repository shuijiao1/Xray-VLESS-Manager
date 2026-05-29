#!/usr/bin/env bash
VERSION="0.1.5"
set -Eeuo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
: "${XRAY_DIR:=/usr/local/etc/xray}"
: "${XRAY_BIN:=/usr/local/bin/xray}"
: "${XRAY_SERVICE:=/etc/systemd/system/xray.service}"
CONFIG=$XRAY_DIR/config.json
CLIENT_TXT=$XRAY_DIR/client.txt
CLIENT_JSON=$XRAY_DIR/client.json
: "${INSTALL_SCRIPT_URL:=https://github.com/XTLS/Xray-install/raw/main/install-release.sh}"

need_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo -e "${RED}请使用 root 运行${NC}"; exit 1; }; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
rand_uuid() { $XRAY_BIN uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid; }
rand_hex() { openssl rand -hex "${1:-8}"; }
public_ip() { curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || curl -4fsS --max-time 4 https://ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP"; }
json_escape() { jq -rn --arg v "$1" '$v|@uri'; }
require_value() { local name=$1 value=${2:-}; [[ -n $value ]] || { echo -e "${RED}${name} 生成失败，请检查 Xray-core 版本。${NC}"; return 1; }; }

status_text() { [[ -x $XRAY_BIN ]] && echo -e "${GREEN}已安装${NC}" || echo -e "${RED}未安装${NC}"; }
run_text() { systemctl is-active --quiet xray 2>/dev/null && echo -e "${GREEN}运行中${NC}" || echo -e "${RED}未运行${NC}"; }
legacy_run_text() { if systemctl is-active --quiet xray-vless 2>/dev/null; then echo -e "${YELLOW}旧服务运行中${NC}"; fi; }
pause() { read -r -p "按回车继续..." _ || true; }

install_deps() {
  if has_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip jq openssl ca-certificates
  elif has_cmd dnf; then
    dnf install -y curl unzip jq openssl ca-certificates
  elif has_cmd yum; then
    yum install -y curl unzip jq openssl ca-certificates
  else
    echo -e "${RED}不支持的系统：需要 apt/dnf/yum${NC}"; exit 1
  fi
}

install_xray() {
  install_deps
  bash -c "$(curl -LfsS "$INSTALL_SCRIPT_URL")" @ install
  systemctl enable xray >/dev/null 2>&1 || true
}

ensure_xray() { [[ -x $XRAY_BIN ]] || install_xray; }

extract_first_uuid() { grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$1" 2>/dev/null | head -n1 | tr 'A-F' 'a-f'; }
extract_first_port() { jq -r '.inbounds[0].port // empty' "$1" 2>/dev/null | head -n1; }
extract_first_network() { jq -r '.inbounds[0].streamSettings.network // "tcp"' "$1" 2>/dev/null | head -n1; }
extract_first_security() { jq -r '.inbounds[0].streamSettings.security // "none"' "$1" 2>/dev/null | head -n1; }

write_client_from_current_config() {
  [[ -f $CONFIG ]] || return 1
  local ip port uuid network security uri title
  ip=$(public_ip)
  port=$(extract_first_port "$CONFIG")
  uuid=$(extract_first_uuid "$CONFIG")
  network=$(extract_first_network "$CONFIG")
  security=$(extract_first_security "$CONFIG")
  [[ -n ${port:-} && -n ${uuid:-} ]] || return 1
  case "$network/$security" in
    tcp/none|tcp/"")
      write_client_json "$ip" "$port" "$uuid" tcp none
      uri="vless://${uuid}@${ip}:${port}?encryption=none&security=none&type=tcp#VLESS-TCP-${ip}"
      title="VLESS TCP 明文（官方模板：VLESS-TCP；不推荐公网裸跑）"
      write_summary "$title" "$uri" "UUID: $uuid" "端口: $port"
      ;;
    *)
      echo "当前配置类型为 ${network}/${security}，旧版本未保存客户端摘要，请重新安装该模式以生成完整客户端配置。"
      return 1
      ;;
  esac
}

migrate_legacy_service() {
  [[ -f /etc/systemd/system/xray-vless.service || -f /etc/xray/vless-basic.json ]] || return 0
  if [[ ! -f $CONFIG && -f /etc/xray/vless-basic.json ]]; then
    mkdir -p "$XRAY_DIR"
    cp -a /etc/xray/vless-basic.json "$CONFIG"
  fi
  if [[ -f $CONFIG ]]; then
    write_common_service
    systemctl disable --now xray-vless.service >/dev/null 2>&1 || true
    systemctl restart xray || systemctl start xray
    write_client_from_current_config >/dev/null 2>&1 || true
    echo "已迁移旧 xray-vless.service 到 xray.service"
  fi
}

write_common_service() {
  mkdir -p "$XRAY_DIR"
  cat > "$XRAY_SERVICE" <<SERVICE
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_BIN run -config $CONFIG
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable xray >/dev/null 2>&1 || true
}

ask_port() { local def=${1:-443} p; read -r -p "端口 [${def}]: " p || true; echo "${p:-$def}"; }
ask_sni() { local def=${1:-www.microsoft.com} d; read -r -p "伪装域名/SNI [${def}]: " d || true; echo "${d:-$def}"; }
ask_path() { local def="/${1:-$(rand_hex 4)}" p; read -r -p "路径 [${def}]: " p || true; p=${p:-$def}; [[ $p == /* ]] || p="/$p"; echo "$p"; }
ask_domain() { local d; while [[ -z ${d:-} ]]; do read -r -p "你的域名: " d || true; done; echo "$d"; }

base_config() {
  cat <<JSON
{
  "log": { "loglevel": "warning" },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
    ]
  },
  "inbounds": [],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
JSON
}

save_and_restart() {
  write_common_service
  $XRAY_BIN test -config "$CONFIG"
  systemctl restart xray
}

write_client_json() {
  local address=$1 port=$2 uuid=$3 network=$4 security=$5 flow=${6:-} sni=${7:-} public=${8:-} shortid=${9:-} path=${10:-} service=${11:-} enc=${12:-none}
  jq -n \
    --arg address "$address" --argjson port "$port" --arg uuid "$uuid" --arg network "$network" --arg security "$security" \
    --arg flow "$flow" --arg sni "$sni" --arg public "$public" --arg shortid "$shortid" --arg path "$path" --arg service "$service" --arg enc "$enc" '
  {
    log:{loglevel:"warning"},
    inbounds:[{listen:"127.0.0.1",port:10808,protocol:"socks",settings:{udp:true},sniffing:{enabled:true,destOverride:["http","tls","quic"],routeOnly:true}}],
    outbounds:[{
      tag:"proxy", protocol:"vless",
      settings:{vnext:[{address:$address,port:$port,users:[({id:$uuid,encryption:$enc} + (if $flow != "" then {flow:$flow} else {} end))]}]},
      streamSettings:(
        {network:$network,security:(if $security == "" then "none" else $security end)} +
        (if $security == "reality" then {realitySettings:{fingerprint:"chrome",serverName:$sni,publicKey:$public,shortId:$shortid,spiderX:"/"}} else {} end) +
        (if $network == "ws" then {wsSettings:{path:$path,headers:{Host:$sni}}} else {} end) +
        (if $network == "grpc" then {grpcSettings:{serviceName:$service,multiMode:false}} else {} end) +
        (if $network == "xhttp" then {xhttpSettings:{path:$path}} else {} end) +
        (if $security == "tls" then {tlsSettings:{serverName:$sni,fingerprint:"chrome"}} else {} end)
      )
    },{tag:"direct",protocol:"freedom"},{tag:"block",protocol:"blackhole"}]
  }' > "$CLIENT_JSON"
}

write_summary() {
  local title=$1 uri=$2
  shift 2
  {
    echo "$title"
    echo "$uri"
    echo
    for item in "$@"; do echo "$item"; done
    echo
    echo "客户端 JSON: $CLIENT_JSON"
    echo "服务端配置: $CONFIG"
  } > "$CLIENT_TXT"
  cat "$CLIENT_TXT"
}

install_plain_vless_tcp() {
  ensure_xray
  local port uuid ip uri
  port=$(ask_port 443); uuid=$(rand_uuid); ip=$(public_ip)
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"level":0,"email":"vless-tcp"}],"decryption":"none"},
    "streamSettings":{"network":"tcp"},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" tcp none
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=none&security=none&type=tcp#VLESS-TCP-${ip}"
  write_summary "VLESS TCP 明文（官方模板：VLESS-TCP；不推荐公网裸跑）" "$uri" "UUID: $uuid" "端口: $port"
}

install_vless_reality_vision() {
  ensure_xray
  local port uuid sni keys private public shortid ip uri
  port=$(ask_port 443); sni=$(ask_sni "www.microsoft.com"); uuid=$(rand_uuid); shortid=$(rand_hex 8); ip=$(public_ip)
  keys=$($XRAY_BIN x25519); private=$(awk -F': ' '/Private key/{print $2}' <<<"$keys"); public=$(awk -F': ' '/Public key/{print $2}' <<<"$keys"); require_value "PrivateKey" "$private"; require_value "PublicKey" "$public"
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private" --arg shortid "$shortid" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"flow":"xtls-rprx-vision","email":"vision-reality"}],"decryption":"none"},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"target":($sni+":443"),"xver":0,"serverNames":[$sni],"privateKey":$private,"shortIds":[$shortid]}},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" tcp reality xtls-rprx-vision "$sni" "$public" "$shortid"
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${public}&sid=${shortid}&type=tcp&headerType=none#VLESS-Vision-Reality-${ip}"
  write_summary "VLESS + XTLS Vision + REALITY（官方模板：VLESS-TCP-XTLS-Vision-REALITY）" "$uri" "UUID: $uuid" "PublicKey: $public" "ShortId: $shortid" "SNI: $sni" "端口: $port"
}

install_vless_tcp_reality() {
  ensure_xray
  local port uuid sni keys private public shortid ip uri
  port=$(ask_port 443); sni=$(ask_sni "www.microsoft.com"); uuid=$(rand_uuid); shortid=$(rand_hex 8); ip=$(public_ip)
  keys=$($XRAY_BIN x25519); private=$(awk -F': ' '/Private key/{print $2}' <<<"$keys"); public=$(awk -F': ' '/Public key/{print $2}' <<<"$keys"); require_value "PrivateKey" "$private"; require_value "PublicKey" "$public"
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private" --arg shortid "$shortid" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"flow":"","email":"tcp-reality"}],"decryption":"none"},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"target":($sni+":443"),"xver":0,"serverNames":[$sni],"privateKey":$private,"shortIds":[$shortid]}},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" tcp reality "" "$sni" "$public" "$shortid"
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public}&sid=${shortid}&type=tcp&headerType=none#VLESS-TCP-Reality-${ip}"
  write_summary "VLESS TCP + REALITY（官方模板：VLESS-TCP-REALITY）" "$uri" "UUID: $uuid" "PublicKey: $public" "ShortId: $shortid" "SNI: $sni" "端口: $port"
}

install_vless_ws_tls() {
  ensure_xray
  local port uuid domain path cert key uri
  port=$(ask_port 443); domain=$(ask_domain); path=$(ask_path "ws$(rand_hex 3)"); uuid=$(rand_uuid)
  cert="$XRAY_DIR/${domain}.crt"; key="$XRAY_DIR/${domain}.key"
  mkdir -p "$XRAY_DIR"
  echo -e "${YELLOW}说明：此模式按官方 WS/TLS 模板生成。初版使用自签证书；生产更建议 Caddy/Nginx/ACME 前置。${NC}"
  openssl ecparam -genkey -name prime256v1 -out "$key"
  openssl req -new -x509 -key "$key" -out "$cert" -days 3650 -subj "/CN=${domain}" >/dev/null 2>&1
  chown nobody:nogroup "$key" "$cert" 2>/dev/null || chown nobody:nobody "$key" "$cert" 2>/dev/null || true
  chmod 640 "$key" 2>/dev/null || true
  chmod 644 "$cert" 2>/dev/null || true
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg domain "$domain" --arg path "$path" --arg cert "$cert" --arg key "$key" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"level":0,"email":"ws-tls"}],"decryption":"none"},
    "streamSettings":{"network":"ws","security":"tls","tlsSettings":{"serverName":$domain,"certificates":[{"certificateFile":$cert,"keyFile":$key}]},"wsSettings":{"path":$path}},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}
  }]' > "$CONFIG"
  write_client_json "$domain" "$port" "$uuid" ws tls "" "$domain" "" "" "$path"
  save_and_restart
  uri="vless://${uuid}@${domain}:${port}?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=$(json_escape "$path")#VLESS-WS-TLS-${domain}"
  write_summary "VLESS + WebSocket + TLS（参考官方：VLESS-WSS-Nginx / VLESS-TCP-TLS-WS）" "$uri" "UUID: $uuid" "域名: $domain" "路径: $path" "端口: $port"
}

install_vless_grpc_reality() {
  ensure_xray
  local port uuid sni keys private public shortid service ip uri
  port=$(ask_port 443); sni=$(ask_sni "www.microsoft.com"); uuid=$(rand_uuid); shortid=$(rand_hex 8); service="grpc$(rand_hex 3)"; ip=$(public_ip)
  keys=$($XRAY_BIN x25519); private=$(awk -F': ' '/Private key/{print $2}' <<<"$keys"); public=$(awk -F': ' '/Public key/{print $2}' <<<"$keys"); require_value "PrivateKey" "$private"; require_value "PublicKey" "$public"
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private" --arg shortid "$shortid" --arg service "$service" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"flow":"","email":"grpc-reality"}],"decryption":"none"},
    "streamSettings":{"network":"grpc","security":"reality","realitySettings":{"show":false,"target":($sni+":443"),"xver":0,"serverNames":[$sni],"privateKey":$private,"shortIds":[$shortid]},"grpcSettings":{"serviceName":$service}},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" grpc reality "" "$sni" "$public" "$shortid" "" "$service"
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public}&sid=${shortid}&type=grpc&serviceName=${service}&mode=gun#VLESS-gRPC-Reality-${ip}"
  write_summary "VLESS + gRPC + REALITY（官方模板：VLESS-gRPC-REALITY）" "$uri" "UUID: $uuid" "PublicKey: $public" "ShortId: $shortid" "SNI: $sni" "serviceName: $service" "端口: $port"
}

install_vless_xhttp_reality() {
  ensure_xray
  local port uuid sni keys private public shortid path ip uri
  port=$(ask_port 443); sni=$(ask_sni "www.microsoft.com"); path=$(ask_path "xhttp$(rand_hex 3)"); uuid=$(rand_uuid); shortid=$(rand_hex 8); ip=$(public_ip)
  keys=$($XRAY_BIN x25519); private=$(awk -F': ' '/Private key/{print $2}' <<<"$keys"); public=$(awk -F': ' '/Public key/{print $2}' <<<"$keys"); require_value "PrivateKey" "$private"; require_value "PublicKey" "$public"
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg sni "$sni" --arg private "$private" --arg shortid "$shortid" --arg path "$path" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"flow":"","email":"xhttp-reality"}],"decryption":"none"},
    "streamSettings":{"network":"xhttp","xhttpSettings":{"path":$path},"security":"reality","realitySettings":{"show":false,"target":($sni+":443"),"serverNames":[$sni],"privateKey":$private,"shortIds":[$shortid]}},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" xhttp reality "" "$sni" "$public" "$shortid" "$path"
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${public}&sid=${shortid}&type=xhttp&path=$(json_escape "$path")#VLESS-XHTTP-Reality-${ip}"
  write_summary "VLESS + XHTTP + REALITY（官方模板：VLESS-XHTTP-Reality，建议 Xray >= v25.3.6）" "$uri" "UUID: $uuid" "PublicKey: $public" "ShortId: $shortid" "SNI: $sni" "路径: $path" "端口: $port"
}

install_vless_encryption_tcp() {
  ensure_xray
  local port uuid ip enc out uri
  port=$(ask_port 443); uuid=$(rand_uuid); ip=$(public_ip)
  if ! $XRAY_BIN help vlessenc >/dev/null 2>&1; then
    echo -e "${RED}当前 Xray-core 不支持 vlessenc，请先安装/更新到支持 VLESS Encryption 的版本。${NC}"
    return 1
  fi
  out=$($XRAY_BIN vlessenc 2>&1 || true)
  enc=$(grep -Eo "mlkem768x25519plus\.[^[:space:]\"'\`<>]+" <<<"$out" | head -n1 || true)
  if [[ -z $enc ]]; then
    echo -e "${YELLOW}没有自动识别到 vlessenc 输出，请手动粘贴 encryption 字符串。${NC}"
    echo "$out"
    read -r -p "encryption: " enc
  fi
  mkdir -p "$XRAY_DIR"
  base_config | jq --argjson port "$port" --arg uuid "$uuid" --arg enc "$enc" '.inbounds=[{
    "listen":"0.0.0.0", "port":$port, "protocol":"vless",
    "settings":{"clients":[{"id":$uuid,"level":0,"email":"vless-encryption"}],"decryption":$enc},
    "streamSettings":{"network":"tcp"},
    "sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}
  }]' > "$CONFIG"
  write_client_json "$ip" "$port" "$uuid" tcp none "" "" "" "" "" "" "$enc"
  save_and_restart
  uri="vless://${uuid}@${ip}:${port}?encryption=$(json_escape "$enc")&security=none&type=tcp#VLESS-Encryption-${ip}"
  write_summary "VLESS Encryption TCP（官方文档：VLESS Encryption / xray vlessenc）" "$uri" "注意: 客户端必须支持同款 encryption 字段" "UUID: $uuid" "端口: $port" "encryption: $enc"
}

show_client() { [[ -f $CLIENT_TXT ]] || write_client_from_current_config >/dev/null 2>&1 || true; [[ -f $CLIENT_TXT ]] && cat "$CLIENT_TXT" || echo "暂无配置"; }
show_log() { journalctl -u xray -n 80 --no-pager; }
uninstall_xray() {
  read -r -p "确认卸载 Xray 并删除配置？[y/N] " yn
  [[ $yn =~ ^[Yy]$ ]] || return 0
  systemctl disable --now xray 2>/dev/null || true
  rm -f "$XRAY_SERVICE"
  rm -rf "$XRAY_DIR" /usr/local/share/xray /usr/local/bin/xray
  systemctl daemon-reload
  echo "已卸载"
}

menu() {
  clear || true
  echo -e "${CYAN}============================================${NC}"
  echo -e "${CYAN} Xray VLESS Manager${NC}"
  echo -e "${CYAN} Repo: Xray-VLESS-Manager${NC}"
  echo -e "${CYAN} Author: shuijiao${NC}"
  echo -e "${CYAN}============================================${NC}"
  echo -e "安装状态: $(status_text)"
  echo -e "运行状态: $(run_text)"
  local legacy_status
  legacy_status=$(legacy_run_text)
  [[ -n $legacy_status ]] && echo -e "旧服务状态: $legacy_status（建议选择 13 迁移）"
  echo
  echo -e "${BLUE}=== 基础功能 ===${NC}"
  echo " 1) 安装/更新 Xray-core"
  echo " 2) 安装 VLESS TCP 明文"
  echo " 3) 安装 VLESS + XTLS Vision + REALITY（推荐）"
  echo " 4) 安装 VLESS TCP + REALITY"
  echo " 5) 安装 VLESS + WebSocket + TLS"
  echo " 6) 安装 VLESS + gRPC + REALITY"
  echo " 7) 安装 VLESS + XHTTP + REALITY"
  echo " 8) 安装 VLESS Encryption TCP"
  echo
  echo -e "${BLUE}=== 服务管理 ===${NC}"
  echo " 9) 查看客户端配置"
  echo "10) 重启 Xray"
  echo "11) 查看日志"
  echo
  echo -e "${BLUE}=== 系统功能 ===${NC}"
  echo "12) 卸载 Xray"
  echo "13) 迁移旧版 xray-vless.service"
  echo " 0) 退出"
  echo
}

main() {
  need_root
  while true; do
    menu
    read -r -p "请选择: " choice || exit 0
    case "$choice" in
      1) install_xray; pause;;
      2) install_plain_vless_tcp; pause;;
      3) install_vless_reality_vision; pause;;
      4) install_vless_tcp_reality; pause;;
      5) install_vless_ws_tls; pause;;
      6) install_vless_grpc_reality; pause;;
      7) install_vless_xhttp_reality; pause;;
      8) install_vless_encryption_tcp; pause;;
      9) show_client; pause;;
      10) systemctl restart xray && systemctl status xray --no-pager -l; pause;;
      11) show_log; pause;;
      12) uninstall_xray; pause;;
      13) migrate_legacy_service; pause;;
      0) exit 0;;
      *) echo "无效选择"; pause;;
    esac
  done
}
main "$@"
