#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$PROJECT_DIR/argox.sh"
TEST_BASE=${TMPDIR:-/tmp}
[[ -d "$TEST_BASE" && -w "$TEST_BASE" ]] || TEST_BASE="$PROJECT_DIR"
TEST_ROOT=$(mktemp -d "$TEST_BASE/argox-release-test.XXXXXX")
TEST_WORK="$TEST_ROOT/work"
TEST_TEMP="$TEST_ROOT/tmp"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail 'jq is required'
bash -n "$SCRIPT"
grep -Fq 'exec bash "$WORK_DIR/argox.sh" "\$@"' "$SCRIPT" ||
  fail 'installed argox launcher does not forward to the installed script'
if grep -Fq 'bash /usr/bin/argox' "$SCRIPT"; then
  fail 'recursive argox launcher is still present'
fi

# Load function definitions without executing argox.sh's root/install/menu path.
# Replace its fixed system paths so this test cannot touch an existing install.
TEST_SOURCE="$TEST_ROOT/argox-functions.sh"
awk '/^check_cdn$/{exit} {print}' "$SCRIPT" |
  sed \
    -e "s|^WORK_DIR=.*|WORK_DIR='$TEST_WORK'|" \
    -e "s|^TEMP_DIR=.*|TEMP_DIR='$TEST_TEMP'|" \
    > "$TEST_SOURCE"
source "$TEST_SOURCE"
trap cleanup EXIT

# The sourced script intentionally does not select a UI language because its
# normal entry path is skipped in this test. Set it before exercising helpers
# that render localized messages under `set -u`.
L='E'

mkdir -p "$TEST_WORK/subscribe"
ln -s "$(command -v jq)" "$TEST_WORK/jq"

if (
  INSTALL_NGINX='n'
  ARGO_DOMAIN='xhttp.example.com'
  ARGO_AUTH='REPLACE_WITH_CLOUDFLARE_TUNNEL_TOKEN_OR_JSON'
  ARGO_TOKEN=''
  ARGO_JSON=''
  argo_variable >/dev/null 2>&1
); then
  fail 'invalid named-tunnel credentials were accepted'
fi

is_fixed_argo_domain 'xhttp.example.com' || fail 'valid fixed Tunnel hostname was rejected'
is_fixed_argo_domain 'XHTTP.EXAMPLE.COM' || fail 'hostname validation should be case-insensitive'
if is_fixed_argo_domain 'demo.trycloudflare.com'; then
  fail 'temporary Tunnel hostname was accepted by the fixed-domain flow'
fi
if is_fixed_argo_domain 'https://xhttp.example.com'; then
  fail 'URL was accepted where a fixed Tunnel hostname is required'
fi

TEST_TUNNEL_TOKEN=$(printf 'A%.0s' {1..160})
is_cloudflare_tunnel_token "$TEST_TUNNEL_TOKEN" || fail 'URL-safe Tunnel token was rejected'
is_cloudflare_tunnel_credential "$TEST_TUNNEL_TOKEN" || fail 'Tunnel token was rejected as a credential'
is_cloudflare_tunnel_credential '{"AccountTag":"test","TunnelSecret":"secret","TunnelID":"test-id"}' ||
  fail 'one-line Tunnel JSON was rejected as a credential'
if is_cloudflare_tunnel_credential 'REPLACE_WITH_CLOUDFLARE_TUNNEL_TOKEN_OR_JSON'; then
  fail 'credential placeholder was accepted'
fi

if ! (
  INSTALL_NGINX='n'
  ARGO_DOMAIN='xhttp.example.com'
  ARGO_AUTH="$TEST_TUNNEL_TOKEN"
  ARGO_TOKEN=''
  ARGO_JSON=''
  SERVER_IP=''
  check_system_ip() { SERVER_IP_DEFAULT='198.51.100.7'; }
  argo_variable
  [[ "$ARGO_TOKEN" == "$TEST_TUNNEL_TOKEN" && -z "${ARGO_JSON:-}" ]]
); then
  fail 'valid fixed Tunnel token was not accepted by argo_variable'
fi

if ! (
  refresh_port_snapshot() { :; }
  is_port_in_use() { [[ "$1" == '30000' ]]; }
  [[ "$(find_available_tcp_port 30000 30002)" == '30001' ]]
); then
  fail 'guided installer did not select the first free local port'
fi

if ! (
  find_available_tcp_port() {
    [[ "$1" == "$START_PORT_DEFAULT" ]] && printf '%s' '30001' || printf '%s' '8081'
  }
  check_system_ip() { SERVER_IP_DEFAULT='198.51.100.7'; }
  cat() {
    [[ "$1" == '/proc/sys/kernel/random/uuid' ]] && {
      printf '%s\n' '11111111-2222-3333-4444-555555555555'
      return 0
    }
    command cat "$@"
  }
  SERVER_IP=''
  apply_guided_xhttp_infra_defaults
  [[ "${INSTALL_PROTOCOLS[*]}" == 'i' ]] &&
  [[ "$ALLOW_LEGACY_PROTOCOLS" == 'n' ]] &&
  [[ "$SERVER_PORT" == '443' ]] &&
  [[ "$START_PORT" == '30001' && "$NGINX_PORT" == '8081' ]] &&
  [[ "$SERVER_IP" == '198.51.100.7' ]] &&
  [[ "$WS_PATH" =~ ^xh[0-9a-f]{16}$ ]]
); then
  fail 'guided installer infra defaults are incomplete or unsafe'
fi

# reading_yn / reading_text_default / reading_xhttp_mode / reading_ech_query_domain /
# reading_ech_dns: pressing Enter (blank input) must keep the caller-supplied default,
# an unrecognised value must warn and fall back to the default rather than silently
# accepting garbage, and a valid manual override must be honoured verbatim.
if ! (
  reading() { printf -v "$2" '%s' ''; }
  warning() { :; }
  reading_yn 'prompt' 'V1' 'y'
  reading_yn 'prompt' 'V2' 'n'
  reading_text_default 'prompt' 'V3' 'default-value'
  reading_xhttp_mode 'packet-up'
  reading_ech_query_domain 'cloudflare-ech.com'
  reading_ech_dns 'https://1.1.1.1/dns-query'
  [[ "$V1" == 'y' && "$V2" == 'n' && "$V3" == 'default-value' ]] &&
  [[ "$XHTTP_CDN_MODE" == 'packet-up' ]] &&
  [[ "$ECH_QUERY_DOMAIN" == 'cloudflare-ech.com' ]] &&
  [[ "$ECH_DNS" == 'https://1.1.1.1/dns-query' ]]
); then
  fail 'wizard prompt helpers did not keep defaults on blank (Enter) input'
fi

if ! (
  reading() { printf -v "$2" '%s' 'n'; }
  reading_yn 'prompt' 'V1' 'y'
  [[ "$V1" == 'n' ]]
); then
  fail 'reading_yn did not honour an explicit manual override'
fi

if ! (
  reading() { printf -v "$2" '%s' 'stream-up'; }
  reading_xhttp_mode 'packet-up'
  [[ "$XHTTP_CDN_MODE" == 'stream-up' ]]
); then
  fail 'reading_xhttp_mode did not honour a valid manual override'
fi

if ! (
  reading() { printf -v "$2" '%s' 'not-a-real-mode'; }
  warning() { :; }
  reading_xhttp_mode 'packet-up'
  [[ "$XHTTP_CDN_MODE" == 'packet-up' ]]
); then
  fail 'reading_xhttp_mode did not fall back to the default on an invalid choice'
fi

if ! (
  reading() { printf -v "$2" '%s' 'not-a-valid-dns-url'; }
  warning() { :; }
  reading_ech_dns 'https://1.1.1.1/dns-query'
  [[ "$ECH_DNS" == 'https://1.1.1.1/dns-query' ]]
); then
  fail 'reading_ech_dns did not fall back to the default on an invalid resolver URL'
fi

if ! (
  WORK_DIR="$TEST_ROOT/guided-work"
  CUSTOM_FILE="$WORK_DIR/custom"
  TEST_GUIDED_CALLS=''
  TEST_READING_CALL=0
  reading() {
    TEST_READING_CALL=$(( TEST_READING_CALL + 1 ))
    if [[ "$TEST_READING_CALL" -eq 1 ]]; then
      printf -v "$2" '%s' 'XHTTP.EXAMPLE.COM'
    else
      # 之后每一步都直接回车，验证全程"回车即采用默认值"能顺利跑完整个向导。
      printf -v "$2" '%s' ''
    fi
  }
  read() {
    local _target="${!#}"
    printf -v "$_target" '%s' "$TEST_TUNNEL_TOKEN"
  }
  find_available_tcp_port() {
    [[ "$1" == "$START_PORT_DEFAULT" ]] && printf '%s' '30001' || printf '%s' '8081'
  }
  check_system_ip() { SERVER_IP_DEFAULT='198.51.100.7'; }
  cat() {
    [[ "$1" == '/proc/sys/kernel/random/uuid' ]] && {
      printf '%s\n' '11111111-2222-3333-4444-555555555555'
      return 0
    }
    command cat "$@"
  }
  install_argox() { TEST_GUIDED_CALLS+='install '; }
  export_list() { TEST_GUIDED_CALLS+='export '; }
  create_shortcut() { TEST_GUIDED_CALLS+='shortcut'; }
  SERVER_IP=''
  guided_xhttp_install >/dev/null
  [[ "$ARGO_DOMAIN" == 'xhttp.example.com' ]] &&
  [[ "$ARGO_AUTH" == "$TEST_TUNNEL_TOKEN" ]] &&
  [[ "$NONINTERACTIVE_INSTALL" == 'noninteractive_install' ]] &&
  [[ "$TEST_GUIDED_CALLS" == 'install export shortcut' ]] &&
  [[ "$SERVER" == 'www.cloudflare.com' ]] &&
  [[ "$ENABLE_VLESS_PQC" == 'y' && "$VLESS_PQC_STRICT" == 'y' && "$VLESS_PQC_DISABLE_0RTT" == 'y' ]] &&
  [[ "$XHTTP_CDN_MODE" == 'packet-up' ]] &&
  [[ "$ENABLE_ECH" == 'y' && "$ECH_STRICT" == 'y' ]] &&
  [[ "$ECH_QUERY_DOMAIN" == 'cloudflare-ech.com' ]] &&
  [[ "$ECH_DNS" == 'https://1.1.1.1/dns-query' ]]
); then
  fail 'guided installer wizard did not walk all key fields with correct Enter-to-accept defaults'
fi

grep -Fq "g ) GUIDED_XHTTP_INSTALL='guided_xhttp_install'" "$SCRIPT" ||
  fail 'the argox -g guided-install entry point is missing'
grep -Fq 'OPTION[3]="3.  $(text 133)"' "$SCRIPT" ||
  fail 'the guided-install menu entry is missing'

INSTALL_PROTOCOLS=(i)
REINSTALL_TAGS=()
ENABLE_ECH='y'
ECH_STRICT='y'
ECH_CONFIG=''
ECH_QUERY_DOMAIN='cloudflare-ech.com'
ECH_DNS='https://1.1.1.1/dns-query'
XHTTP_CDN_MODE='packet-up'
ARGO_DOMAIN='xhttp.example.com'
SERVER='www.cloudflare.com'
SERVER_PORT='443'
UUID='11111111-2222-3333-4444-555555555555'
WS_PATH='argox'
VLESS_CLIENT_ENCRYPTION='mlkem768x25519plus.native.1rtt.100-111-1111.75-0-111.test_key'

ech_runtime_values
[[ "$ECH_CLIENT_CONFIG" == 'cloudflare-ech.com+https://1.1.1.1/dns-query' ]] ||
  fail 'dynamic ECH query expression is incorrect'
[[ "$ECH_URI_PARAM" == '&ech=cloudflare-ech.com%2Bhttps%3A%2F%2F1.1.1.1%2Fdns-query' ]] ||
  fail 'ECH URI parameter is not RFC 3986 encoded'
[[ -z "$MIHOMO_TLS_FINGERPRINT" ]] ||
  fail 'Mihomo client-fingerprint must be removed when ECH is enabled'
[[ "$MIHOMO_ECH_OPTS" == *'query-server-name: cloudflare-ech.com'* ]] ||
  fail 'Mihomo ECH lookup domain is incorrect'

write_xray_xhttp_pqc_ech_client
CLIENT_JSON="$TEST_WORK/subscribe/xray-xhttp-pqc-ech.json"
[[ -s "$CLIENT_JSON" ]] || fail 'native Xray client was not generated'

jq -e \
  --arg encryption "$VLESS_CLIENT_ENCRYPTION" \
  --arg ech "$ECH_CLIENT_CONFIG" '
    .outbounds[0].protocol == "vless" and
    .outbounds[0].settings.encryption == $encryption and
    .outbounds[0].streamSettings.network == "xhttp" and
    .outbounds[0].streamSettings.xhttpSettings.mode == "packet-up" and
    .outbounds[0].streamSettings.tlsSettings.echConfigList == $ech and
    .outbounds[0].streamSettings.tlsSettings.serverName == "xhttp.example.com"
  ' "$CLIENT_JSON" >/dev/null || fail 'native Xray client fields are incorrect'

[[ "$(stat -c '%a' "$CLIENT_JSON")" == '600' ]] ||
  fail 'native Xray client permissions must be 0600'

ENABLE_ECH='n'
ech_runtime_values
[[ -z "$ECH_CLIENT_CONFIG" && -z "$ECH_URI_PARAM" ]] ||
  fail 'ECH runtime state was not cleared when disabled'
[[ "$MIHOMO_TLS_FINGERPRINT" == ', client-fingerprint: chrome' ]] ||
  fail 'Mihomo fingerprint fallback was not restored'

# Run the complete subscription exporter with all host/system interactions
# stubbed. This exercises the actual URI and Mihomo serialization code.
check_arch() { ARGO_ARCH='amd64'; }
check_system_info() {
  SYS='ArgoX test'
  VIRT='test'
  ARGO_DAEMON_FILE="$TEST_ROOT/no-argo.service"
  DAEMON_RUN_PATTERN='ExecStart='
}
check_system_ip() {
  WAN4='192.0.2.1'; WAN6=''
  COUNTRY4='test'; COUNTRY6='test'
  ASNORG4='test'; ASNORG6='test'
}
check_install() {
  STATUS[0]="$(text 28)"
  STATUS[1]="$(text 28)"
  STATUS[2]="$(text 26)"
  IS_NGINX='no_nginx'
}
fetch_tunnel_domain() { return 0; }
fetch_nodes_value() { return 0; }
vless_pqc_runtime_values() { return 0; }
get_installed_protocols() { printf '%s\n' 'xhttp-h1.1-cdn'; }
qrencode_print() { return 0; }
statistics_of_run-times() { return 0; }
pgrep() { return 0; }
nginx() { printf '%s\n' 'nginx version: test' >&2; }

printf '%s\n' '#!/usr/bin/env bash' 'echo "cloudflared version test"' > "$TEST_WORK/cloudflared"
printf '%s\n' '#!/usr/bin/env bash' 'echo "Xray test"' > "$TEST_WORK/xray"
chmod 700 "$TEST_WORK/cloudflared" "$TEST_WORK/xray"

ENABLE_ECH='y'
ECH_CONFIG=''
ECH_QUERY_DOMAIN='cloudflare-ech.com'
ECH_DNS='https://1.1.1.1/dns-query'
XHTTP_CDN_MODE='packet-up'
VLESS_CLIENT_ENCRYPTION_QUERY=$(url_encode "$VLESS_CLIENT_ENCRYPTION")
ech_runtime_values
set +eu
export_list > "$TEST_ROOT/export-output.txt"
EXPORT_RC=$?
set -eu
[[ "$EXPORT_RC" -eq 0 ]] || fail 'subscription exporter returned an error'

PROXIES="$TEST_WORK/subscribe/proxies"
[[ -s "$PROXIES" ]] || fail 'Mihomo provider was not generated'
grep -Fq 'mode: packet-up' "$PROXIES" || fail 'Mihomo XHTTP mode is incorrect'
grep -Fq 'ech-opts: {enable: true, query-server-name: cloudflare-ech.com}' "$PROXIES" ||
  fail 'Mihomo ECH options are missing'
if grep -Fq 'client-fingerprint' "$PROXIES"; then
  fail 'Mihomo provider contains a fingerprint that conflicts with ECH'
fi
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 - "$PROXIES" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
proxy = data["proxies"][0]
assert proxy["type"] == "vless"
assert proxy["network"] == "xhttp"
assert proxy["xhttp-opts"]["mode"] == "packet-up"
assert proxy["ech-opts"]["enable"] is True
assert proxy["ech-opts"]["query-server-name"] == "cloudflare-ech.com"
assert "client-fingerprint" not in proxy
PY
fi

V2RAYN_LINKS=$(base64 -d "$TEST_WORK/subscribe/base64")
grep -Fq 'type=xhttp' <<< "$V2RAYN_LINKS" || fail 'standard VLESS XHTTP URI is missing'
grep -Fq 'mode=packet-up' <<< "$V2RAYN_LINKS" || fail 'standard URI XHTTP mode is incorrect'
grep -Fq 'ech=cloudflare-ech.com%2Bhttps%3A%2F%2F1.1.1.1%2Fdns-query' <<< "$V2RAYN_LINKS" ||
  fail 'standard URI ECH parameter is missing or unencoded'

printf 'PASS: ArgoX release checks\n'
