# Changelog

## 2.3.1-guided-fixed-domain-xhttp-pqc-ech - 2026-08-13

- Added `argox -g` and a fresh-install menu entry for guided fixed-domain
  VLESS + XHTTP + PQC + ECH + Argo + CDN deployment.
- The guided path asks only for the fixed Tunnel hostname and hidden Tunnel
  token/one-line JSON, then selects safe defaults and free local ports.
- Added strict fixed-domain and Tunnel credential validation to prevent
  temporary-tunnel fallback or accidental overwrite of an existing install.

## 2.3.0-vless-xhttp-pqc-ech-argo-cdn - 2026-08-13

- Added the complete fixed-tunnel VLESS + XHTTP + PQC + ECH + Argo + CDN path.
- Changed the CDN XHTTP default to `packet-up` for HTTP-middlebox compatibility.
- Added strict ECH settings with dynamic HTTPS-record lookup through Cloudflare DoH.
- Added the standard VLESS URI `ech` parameter.
- Added Mihomo `ech-opts` and removed `client-fingerprint` when ECH is active.
- Added a full native Xray client at `subscribe/xray-xhttp-pqc-ech.json`.
- Added `config-vless-xhttp-pqc-ech-argo-cdn.conf`.
- Fixed the installed `argox` launcher recursively invoking itself.
- Reject invalid named-tunnel credentials instead of silently using Quick Tunnel.
- Replaced third-party default CDN candidates with Cloudflare-owned hostnames.

## 2.2.3-pqc-strong-reality-domain-reality-pqc - 2026-07-06

- Reality Vision / Reality gRPC explicitly join the VLESS PQC strong path.
- Reality server inbound keeps `decryption=mlkem768x25519plus...600s...`.
- Reality client VLESS URI keeps `encryption=mlkem768x25519plus...1rtt...`.
- Clash / Mihomo Reality Vision and Reality gRPC output includes the VLESS `encryption` field.
- Keeps `REALITY_DOMAIN` as the client connection address and `TLS_SERVER` as the Reality SNI/camouflage domain.
- Keeps strong mode defaults: `ENABLE_VLESS_PQC='y'`, `VLESS_PQC_STRICT='y'`, `VLESS_PQC_DISABLE_0RTT='y'`.

## 2.2.2-pqc-strong-reality-domain - 2026-07-06

- Added Reality custom connection domain via `REALITY_DOMAIN`.
- Added install-time input, non-interactive config support, and `argox -d` modification support.
- Preserved manually selected Reality protocols in temporary Argo mode.
