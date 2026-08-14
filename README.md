# ArgoX 2.3.1：VLESS + XHTTP + PQC + ECH + Argo + CDN

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

## 傻瓜式固定域名安装

这是推荐的首次部署方式。先在 Cloudflare Zero Trust 后台完成两件事：

1. 创建 Cloudflare Tunnel。
2. 为该 Tunnel 添加与你要输入的固定域名相同的 Public Hostname。

然后在 VPS 上执行：

```bash
sudo bash argox.sh -c -g
```

也可以直接运行脚本，在首次安装菜单中选择第 `3` 项。流程只会询问：

1. 固定 Tunnel 域名。
2. 该 Tunnel 的 Token（隐藏输入）或单行 credentials JSON。

其余参数会自动使用安全默认值：`VLESS + XHTTP packet-up`、PQC 1-RTT、
ECH、Cloudflare CDN、随机 UUID 与路径，以及自动避开已占用的本地端口。
该模式拒绝 `trycloudflare.com`、无效凭据和已存在的 ArgoX 安装，避免静默
降级为临时隧道。只有 Tunnel Token/JSON 适用于此引导流程；若要让脚本通过
Cloudflare API 创建 Tunnel，请使用下面的高级模板。

## 高级模板安装

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

## 2.3.2 加固说明

- Cloudflare 侧 XHTTP（`xhttp-h1.1-cdn`）新增完整的 `xhttpSettings.extra`：
  `xPaddingBytes`（请求头随机填充，抵抗长度指纹）、`noSSEHeader`、
  `scMaxEachPostBytes`、`scMinPostsIntervalMs`、`scMaxBufferedPosts`，服务端
  与原生 Xray 客户端（`xray-xhttp-pqc-ech.json`）保持一致。
- 该链路的 TLS 1.3 与浏览器级指纹由 Cloudflare 边缘负责（Cloudflare 现网
  仅提供 TLS 1.2/1.3，且默认启用 1.3），VPS 与 Nginx 之间不做二次 TLS；
  客户端 `fingerprint: "chrome"`（uTLS）会重写整个 ClientHello，因此现网
  实际协商的曲线由 uTLS 决定——较新的 Chrome 本身默认发送
  `X25519MLKEM768` 混合后量子密钥份额，原生客户端里显式写的
  `minVersion/maxVersion/curvePreferences` 是显式声明的兜底值，仅在关闭
  uTLS 指纹伪装时才会真正生效。
- 两个不经过 Cloudflare、由 Xray 自行终止 TLS 的直连备用节点
  （`xhttp-h3-direct`、`trojan-direct`）新增 `minVersion`/`maxVersion` 锁定
  为 `1.3`，并加入 `curvePreferences: ["X25519MLKEM768", "X25519"]`，使
  这条 TLS 握手也具备真实的 ML-KEM-768 + X25519 混合后量子密钥交换。这两
  个节点的 SHA-256 证书指纹校验此前已存在（`FP_SHA256`/`FP_BASE64`，对应
  Mihomo `fingerprint`、sing-box `certificate_public_key_sha256`、URI 中
  的 `pcs`/`hpkp`/`pinSHA256`），本次未改动。

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
