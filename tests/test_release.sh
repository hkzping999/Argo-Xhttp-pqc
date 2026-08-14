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

L='E'
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
