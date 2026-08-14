# ArgoX Hotfix 2.3.1

## VLESS + XHTTP + PQC + ECH + Argo + CDN

- 固定 Cloudflare Tunnel 的 XHTTP CDN 节点默认使用 `packet-up`，适配
  Cloudflare CDN、Argo Tunnel、Nginx HTTP/1.1 回源链路。
- VLESS Encryption 继续使用 `mlkem768x25519plus`；服务端 `decryption`
  使用 `600s`，客户端 `encryption` 强制使用 `1rtt`，默认拒绝 0-RTT。
- 新增 ECH 客户端运行时配置，默认动态查询
  `cloudflare-ech.com+https://1.1.1.1/dns-query`。
- 标准 VLESS URI 新增 `ech` 参数。
- Mihomo 输出新增 `ech-opts`，并在启用 ECH 时自动移除冲突的
  `client-fingerprint`。
- 新增 `/etc/argox/subscribe/xray-xhttp-pqc-ech.json` 原生 Xray 完整
  客户端配置。
- 新增专用非交互模板
  `config-vless-xhttp-pqc-ech-argo-cdn.conf`。
- 默认 CDN 候选仅保留 Cloudflare 自有域名。
- 新增固定域名傻瓜式安装：`sudo bash argox.sh -c -g`，也可在首次安装菜单选择
  第 3 项。仅输入固定 Tunnel 域名和隐藏的 Tunnel Token / 单行 JSON 后继续，
  自动设置 XHTTP、PQC、ECH、CDN、UUID、路径与可用本地端口。
- 引导安装仅接受固定 Tunnel Token / JSON，拒绝临时域名、占位凭据和覆盖已有
  ArgoX 安装；需要先在 Cloudflare 后台为该 Tunnel 配置同名 Public Hostname。

## 升级注意

推荐使用专用模板重新部署。若只替换现有安装的脚本，先备份
`/etc/argox`，再执行：

```bash
sudo install -m 700 argox.sh /etc/argox/argox.sh
sudo sh -c 'printf '\''#!/usr/bin/env bash\nexec bash /etc/argox/argox.sh "$@"\n'\'' > /etc/argox/ax.sh'
sudo chmod 700 /etc/argox/ax.sh
sudo ln -sfn /etc/argox/ax.sh /usr/bin/argox
sudo argox -v
sudo argox -r
sudo argox -n
```

若旧的 XHTTP inbound 仍为 `mode=auto`，可删除再重新添加
`xhttp-h1.1-cdn`，或重新安装以应用 `packet-up`。Cloudflare 区域必须启用
ECH；临时 `trycloudflare.com` 隧道仍不支持本组合。

本版本还修复了旧版 `/usr/bin/argox` 快捷入口递归调用自身的问题，并在固定
隧道凭据无效时直接停止安装，不再静默降级为 Quick Tunnel。
