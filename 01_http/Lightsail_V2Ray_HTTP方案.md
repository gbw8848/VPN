# Lightsail 服务器搭建基于 Xray 的 HTTP/VLESS 代理方案

## 场景概述
- 在 Amazon Lightsail 上部署 Xray（V2Ray 内核），将其作为访问 Google、YouTube 等站点的代理出口。
- 要求通过 Web 面板录入/保存参数，无需手动编辑配置文件。
- 客户端使用 v2rayN，可选择 WebSocket 或 HTTP/2 传输层来满足 “HTTP 协议” 形式的连接。

## 准备工作
1. 准备可解析的域名，将 A 记录指向 Lightsail 实例公网 IP（如用 Cloudflare，可开启 CDN）。
2. 确认实例对外放行 TCP 端口 80 和 443（控制台安全组 + OS 防火墙）。

### 本次示例域名
- 使用 `gbwvpn.anyidphoto.com`（Cloudflare DNS “仅 DNS” 灰色云朵模式）指向 Lightsail 公网 IP `54.80.115.82`，用于 VLESS/V2Ray 节点。
- 若后续需要启用 CDN，可在 Cloudflare 中把代理状态切换成 “开启代理（橙色云朵）”，同时在服务器端保留 443 端口并确保证书匹配。
- 当前服务器已安装宝塔面板（BT Panel），后续可用其管理 Nginx/网站回落、证书或防火墙规则。
- Lightsail 实例操作系统为 Ubuntu（2 GB RAM，2 vCPU，60 GB SSD），支持以 root/SSH 登录执行部署脚本。

## 服务器端部署
1. 使用 root 登录 Lightsail 实例，执行：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
   ```
2. 安装完成后，终端会输出 x-ui 面板地址、默认账号与密码，首次登录后立即修改密码。
3. 在面板 “设置” 中配置智能证书：
   - 填写域名，申请 Let’s Encrypt 证书（需保证 80 端口通畅）。
   - 启用自动续期或定期在面板中检查。
4. 新建入站（推荐 VLESS）：
   - 协议：`VLESS`（或 VMess）。
   - 监听端口：`443`。
   - 传输方式：`ws`（WebSocket）或 `http`（HTTP/2）。
   - `ws` 示例：设置路径 `/subh`，Host 填域名；可回落到本地静态站用于伪装。
   - 勾选 `TLS`，引用申请到的证书与私钥。
5. 若确实需要裸 HTTP 代理，可额外添加一个 `protocol: http` 的入站，但须注意其不加密，易被审查识别。

### 部署脚本（自动配置 VLESS + HTTP/2）
- 脚本路径：`deploy_xray_vless_h2.sh`。上传到服务器后执行：
  ```bash
  chmod +x deploy_xray_vless_h2.sh
  sudo ./deploy_xray_vless_h2.sh
  ```
- 脚本功能：
  - 检查并安装 Xray 内核与依赖。
  - 使用宝塔面板证书目录 `/www/server/panel/vhost/cert/gbwvpn.anyidphoto.com/` 填充 TLS 配置。
  - 生成 VLESS + HTTP/2 配置（路径 `/subh`，端口 443，fallback 到 `127.0.0.1:80` 方便交给宝塔/Nginx）。
  - 自动写入/保存客户端 UUID，并重启 systemd `xray` 服务。
- 脚本执行完成后，终端会输出客户端连接所需的 UUID、域名、端口与路径。将这些参数导入 v2rayN 即可。

## 服务器侧操作要点
- **仅在面板中配置**：x-ui 已封装所有 Xray JSON 项，可完全通过浏览器点击操作，无需 SSH 编辑配置文件。给每个入站起一个别名，便于一键生成/复制分享链接。
- **生成分享链接或订阅**：在面板入站列表选择 `分享` 可得到 `vless://` 或 `vmess://` 链接，或启用“生成订阅”，这样客户端只需粘贴链接即可，避免手工抄写参数。
- **自动证书和续期**：面板申请 Let’s Encrypt 后会自动写入证书路径，后续定时续期；若域名或端口变更，记得在“证书”页面重新申请。
- **防火墙与安全**：确认 Lightsail 网络策略与系统 `ufw`/`firewalld` 已开放 80/443。面板本身建议改用自定义端口并开启面板登录双因素（x-ui 内置验证码），减少被扫风险。
- **回落或伪装站点**：若希望探测访问只看到普通网站，可在面板“回落”设置中指向本地 Nginx/静态站；这样客户端连接仍走 WebSocket/HTTP2，但未授权访问会看到正常页面。
- **监控与日志**：定期在 x-ui 的“面板日志”“Xray 日志”里查看是否有大量失败尝试，必要时调整 UUID 或针对可疑 IP 设置 iptables 限制。
- **证书文件**：TLS/SSL 证书由证书文件和私钥构成，例如 `/root/cert/域名/fullchain.cer` 与 `/root/cert/域名/privkey.key`。x-ui 申请 Let’s Encrypt 后会自动写入这两个路径，手动部署时需在 `tlsSettings` 中填写绝对路径。

## 使用 HTTP/2 传输
- **适用场景**：希望外界看到的是标准 HTTPS/HTTP/2 流量，利用多路复用和二进制分帧以提升伪装与性能。
- **服务器设置**：
  - 在 x-ui 入站编辑页，将 “传输方式” 切换为 `http`，保持 `TLS` 勾选并填写证书路径。
  - `伪装域名(host)` 与 `路径(path)` 需要与域名实际解析一致，可填写多个域名逗号分隔。
  - 若手动写配置，需把 `streamSettings.network` 设为 `http`，并在 `httpSettings` 中提供 `host`、`path` 等字段；端口通常保持 443。
  - 保留 WebSocket 入站作为备份可在遭遇运营商兼容性问题时快速切换。
- **客户端调整**：
  - 在 v2rayN 中将该节点的 “传输协议(network)” 改成 `http`，路径和 Host 与服务器保持一致。
  - `TLS` 仍需启用；导入新的分享链接或刷新订阅后，列表会显示 `http | tls` 的组合。
- **回落与 CDN**：HTTP/2 模式依旧可以配置回落站点和使用 Cloudflare 等 CDN，注意 CDN 控制台开启 HTTP/2/HTTP/3 支持，并确保回源端口 443 打通。

## 客户端配置（v2rayN）
1. 选择 “添加 [VLESS] 配置文件”（或 VMess）。
2. 填写与服务器对应的参数：
   - 地址：域名。
   - 端口：`443`。
   - 用户 ID：面板生成的 UUID。
   - 传输协议：`ws` 或 `http`，路径、Host 必须和服务端一致。
   - TLS：启用后填写 SNI 域名；若使用 Cloudflare，保持 “Full”/“Full (strict)”。
3. 需要本地 HTTP 代理时，可在 v2rayN “本地监听” 中额外开启 HTTP 入口，或直接启用系统代理。

## 客户端图形化录入与自动保存
- v2rayN 的所有连接均通过 GUI 表单维护。像截图所示的 HTTP 表单同样适用：只需在界面中填入域名、端口、用户名/密码（可选）、伪装域名和路径后点击 `确定`，配置即写入 `guiNConfig.json`，无需直接编辑文件。
- 若使用 VLESS/VMess，只要在对应新增窗口手动填写参数或粘贴分享链接，v2rayN 会自动保存，后续在列表中切换即可。
- 建议把服务器端生成的链接（如 `vless://`）复制后使用 v2rayN 的 “从剪贴板导入分享链接” 功能，可一键导入并保存，不必逐项填写。
- v2rayN 支持开启 “自动刷订阅、自动滚动日志”，以及一键启用/关闭 “系统代理” 或 “全局 TUN” 模式，可避免手动修改 Windows 网络代理开关。
- 若经常切换设备，也可以在 x-ui 中生成订阅地址，v2rayN 通过 “订阅设置” 填入 URL 后点 “更新订阅” 即可同步全部配置。
- 正常导入后，连接列表会显示类似 `VLESS  | 别名 | 域名 | 端口 | ws | tls` 的条目（如截图所示），状态栏若标记为 “活动” 则表示连接成功。
- v2rayN 默认在本机开启 `mixed` 端口 `10808`，同时提供 SOCKS5 与 HTTP 服务，应用或浏览器只要指向 `127.0.0.1:10808` 即可走代理。无需每次进系统设置手动切换，直接在 v2rayN 底部按钮启用/关闭 “系统代理” 或 “Tun 模式” 就能控制是否全局生效；若要改端口，可在 “设置 -> 本地监听” 中调整。

## 常见排错
- **连接被远端重置**：多因 Host/路径/UUID/TLS 不匹配，检查客户端参数。
- **证书申请失败**：确认 80 端口对外开放，域名解析已生效。
- **Cloudflare 模式异常**：检查 SSL/TLS 设置与 WebSocket 支持，必要时在 v2rayN 启用跳过证书验证测试。

## 维护建议
- 保持 x-ui 面板与 Xray 内核版本更新。
- 定期查看面板日志，关注异常 IP 并调整防火墙策略。
- 若开启裸 HTTP 入站，建议配合账号密码或在外层套防火墙白名单，以降低滥用风险。
