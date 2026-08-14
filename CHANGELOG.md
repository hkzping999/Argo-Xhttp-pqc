# Changelog

## 2.3.3-oneliner-safe-self-install - 2026-08-13

- **修复 `create_shortcut()` 在 `bash <(wget -qO- .../argox.sh)` /
  `bash <(curl -Ls .../argox.sh)` 一键管道执行方式下的自安装损坏问题。**
  旧逻辑用 `cp "${BASH_SOURCE[0]}" ...` 把"自己"拷贝到
  `/etc/argox/argox.sh`；但通过进程替换（`bash <(...)`）运行时，
  `${BASH_SOURCE[0]}` 指向的是一次性匿名管道（如 `/dev/fd/63`），bash
  解释器本身也在从同一个管道往后读未执行的脚本内容。这种情况下再用 `cp`
  读一次同一个管道，会和 bash 自身的读取进度互相抢占字节：实测会拷贝出
  一份被截断/损坏的文件，且脚本本身会在该步骤后提前终止（后续尚未执行
  的行被 `cp` 提前"吃掉"）。
  现在改为：先用 `[ -f ... ]`（而不是原来的 `[ -r ... ]`）判断来源是不是
  一个真正的普通文件——本地 `git clone` 后直接执行、或已安装在
  `/etc/argox/argox.sh` 时是普通文件，走原来的 `cp` 逻辑；如果不是普通
  文件（管道/进程替换），改为向新增的 `ARGOX_RAW_URL` 常量重新发起一次
  独立的 `wget` 下载，并加上非空校验 + `bash -n` 语法校验，校验通过才
  覆盖安装，避免网络抖动或代理返回错误页面时把坏文件当正式版本装上。
  已用真实的进程替换环境验证：安装后的 `/etc/argox/argox.sh` 与源文件
  逐行一致，且脚本在该步骤后能继续正常往下执行，不再提前退出。
- 新增 `ARGOX_REPO_URL` / `ARGOX_RAW_URL` 两个常量，指向
  `https://github.com/hkzping999/Argo-reality-pqc` 与其 `main` 分支下的
  `argox.sh`，供 `create_shortcut()` 与今后的自更新逻辑复用。
- 语言字符串里遗留的旧仓库地址（`fscarmen/argox`、旧的
  `hkzping999/argox`）统一更新为 `hkzping999/Argo-reality-pqc`。

## 2.3.2-xhttp-tls13-curve-hardening - 2026-08-13

- CDN-facing XHTTP inbound/outbound (`xhttp-h1.1-cdn`, tag `i`, both the
  first-install heredoc and the post-install hot-add path) now sets a
  complete `xhttpSettings.extra` block: `xPaddingBytes` (ClientHello/request
  header length padding against traffic-size fingerprinting),
  `noSSEHeader`, `scMaxEachPostBytes`, `scMinPostsIntervalMs`, and
  `scMaxBufferedPosts`. Previously only `mode` and `path` were set.
- Native Xray client (`subscribe/xray-xhttp-pqc-ech.json`) mirrors the same
  `xhttpSettings.extra` block and now also declares `tlsSettings.minVersion`
  / `maxVersion` = `"1.3"` and `curvePreferences: ["X25519MLKEM768",
  "X25519"]` as an explicit, auditable statement of intent. Note: since
  `fingerprint: "chrome"` (uTLS) stays enabled by default, uTLS — not these
  fields — controls the actual ClientHello and already mimics modern
  Chrome's own hybrid PQC key share; the explicit fields take effect if a
  user later disables uTLS fingerprinting.
- Direct-TLS backup inbounds not behind Cloudflare (`xhttp-h3-direct` tag
  `j`, `trojan-direct` tag `k`) — where Xray terminates TLS itself — now
  pin `minVersion`/`maxVersion` to `1.3` and set
  `curvePreferences: ["X25519MLKEM768", "X25519"]`, enabling a real
  ML-KEM-768/X25519 hybrid post-quantum key exchange at the TLS layer for
  those two nodes (in addition to the existing VLESS Encryption PQC layer
  and the existing SHA-256 certificate pinning already present in their
  Mihomo/sing-box/URI outputs via `FP_SHA256`/`FP_BASE64`).
- Updated both the pretty-printed install-time JSON generator and the
  minified post-install hot-add JSON generator so freshly-added protocols
  match freshly-installed ones.

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
