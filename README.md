# ArgoX 2.3.0：VLESS + XHTTP + PQC + ECH + Argo + CDN

本版本为固定 Cloudflare Tunnel 增加一条完整链路：

```text
客户端
  -> Cloudflare 优选入口（TLS 1.3 + ECH，H2/H1 回退）
  -> Cloudflare CDN / Argo Tunnel
  -> Nginx HTTP/1.1 反代
  -> Xray VLESS + XHTTP packet-up
  -> VLESS Encryption（ML-KEM-768 + X25519，1-RTT）
```

ECH 保护客户端到 Cloudflare 边缘的 ClientHello；PQC 由 VLESS Encryption
提供端到端的混合后量子握手。Cloudflare 负责边缘 TLS/ECH，VPS 不保存 ECH
私钥。

## 前置条件

- 一台受支持的 VPS：Debian、Ubuntu、CentOS、Alpine、Armbian 或 Arch。
- 一个由 Cloudflare 托管的域名。
- 一个固定 Cloudflare Tunnel 的 Token、JSON 或符合脚本提示权限的 API
  Token。
- Cloudflare 区域已启用 ECH。Free 区域通常默认启用；其他套餐可在
  `SSL/TLS -> Edge Certificates -> Encrypted ClientHello (ECH)` 中确认。
- 客户端使用支持 XHTTP、VLESS Encryption 和 ECH 的较新 Xray-core；
  Mihomo 输出需要较新版本。

临时 `trycloudflare.com` 隧道不会输出 XHTTP + PQC + ECH 组合节点。

## 推荐安装

先复制专用模板，至少替换 `ARGO_DOMAIN` 和 `ARGO_AUTH`：

```bash
cp config-vless-xhttp-pqc-ech-argo-cdn.conf my-xhttp.conf
chmod 600 my-xhttp.conf
vi my-xhttp.conf
sudo bash argox.sh -f my-xhttp.conf
```

核心选项如下：

```bash
INSTALL_PROTOCOLS='i'
ENABLE_VLESS_PQC='y'
VLESS_PQC_STRICT='y'
VLESS_PQC_DISABLE_0RTT='y'
XHTTP_CDN_MODE='packet-up'
ENABLE_ECH='y'
ECH_STRICT='y'
ECH_QUERY_DOMAIN='cloudflare-ech.com'
ECH_DNS='https://1.1.1.1/dns-query'
```

`packet-up` 对 CDN、Argo 和 Nginx 中间层兼容性更高，并且不依赖
Cloudflare 的 gRPC 开关。若要使用固定 ECHConfig，可直接设置
`ECH_CONFIG='<base64 ECHConfig>'`；留空则按 `ECH_QUERY_DOMAIN + ECH_DNS`
动态查询并跟随 DNS TTL。

## 客户端输出

安装完成或执行以下命令查看全部链接：

```bash
sudo argox -n
```

脚本会生成：

- 标准 VLESS URI，包含 `type=xhttp`、`mode=packet-up`、PQC `encryption`
  和标准 `ech` 参数。
- Mihomo provider，包含 `encryption`、`xhttp-opts` 与 `ech-opts`。启用
  ECH 时脚本会移除与其冲突的 `client-fingerprint`。
- 原生 Xray 完整客户端配置：
  `/etc/argox/subscribe/xray-xhttp-pqc-ech.json`。默认 SOCKS 端口为
  `127.0.0.1:10808`，HTTP 端口为 `127.0.0.1:10809`。

原生 Xray 配置是本组合的基准输出；当 GUI 客户端尚未完整解析 URI 中的
PQC/ECH 参数时，直接使用该 JSON。

## 验证

发布包自检（不会写入 `/etc`）：

```bash
bash tests/test_release.sh
```

服务端配置检查：

```bash
sudo /etc/argox/xray run -test \
  -c /etc/argox/inbound.json \
  -c /etc/argox/outbound.json
```

确认 XHTTP 与 PQC 已写入：

```bash
sudo /etc/argox/jq -r '
  .inbounds[]
  | select(.tag | endswith("xhttp-h1.1-cdn"))
  | [.streamSettings.network,
     .streamSettings.xhttpSettings.mode,
     .settings.decryption]
  | @tsv
' /etc/argox/inbound.json
```

预期前三项分别以 `xhttp`、`packet-up`、
`mlkem768x25519plus.native.600s.` 开头。客户端配置中的 `encryption`
应以 `mlkem768x25519plus.native.1rtt.` 开头，且 `tlsSettings` 中存在
`echConfigList`。

## 安全说明

- 不要把 Tunnel Token、JSON、PQC 参数或 `/etc/argox/custom` 提交到仓库。
- 脚本默认 `umask 077`，敏感配置写入后使用 0600/0700 权限。
- 第三方 GitHub 下载代理、在线二维码和远程降级脚本保持禁用。
- ECHConfig 会轮换，不建议长期硬编码；动态 DNS 查询通常更可靠。

## 参考

- [Xray XHTTP](https://xtls.github.io/en/config/transports/xhttp.html)
- [Xray TLS / ECH](https://xtls.github.io/en/config/transports/tls.html)
- [Xray VLESS Encryption](https://xtls.github.io/en/config/outbounds/vless.html)
- [Cloudflare ECH](https://developers.cloudflare.com/ssl/edge-certificates/ech/)
- [Mihomo TLS / ECH](https://wiki.metacubex.one/en/config/proxies/tls/)
- [Mihomo XHTTP](https://wiki.metacubex.one/en/config/proxies/transport/)
