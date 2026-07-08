# Solana 升级指导

本文档是本项目的通用升级 Runbook，适用于后续 Solana / Jito Solana / Yellowstone gRPC 的较大版本升级。

核心原则：

- `1-prepare.sh` 只用于首次部署和磁盘初始化，升级时不要执行。
- `2-install-jito-validator.sh` 用于编译并安装目标版本的 Jito Solana validator。
- `3-start.sh` 用于清理旧的 `ledger/accounts/snapshot`，重新下载快照并启动节点。
- 本项目运维策略是：较大升级或重启后，优先重新拉快照启动，避免从旧 ledger 长时间追块但追不上。
- Yellowstone gRPC 的 `libyellowstone_grpc_geyser.so` 需要和 Solana/Agave/Jito Solana 版本线匹配，不能只升级 validator 而继续使用旧版本 geyser 插件。

## 升级前确认

每次升级前先确认这些信息：

- 目标 Jito Solana tag，例如 `v4.1.1-jito`。
- 输入脚本时使用的版本号，例如 `v4.1.1`，不要带 `-jito` 后缀。
- 对应 Yellowstone gRPC release tag。
- 对应 `libyellowstone_grpc_geyser.so` 下载地址。
- 对应 `libyellowstone_grpc_geyser.so` SHA256。
- 是否存在启动参数变更、废弃参数或新增必需参数。
- 是否存在快照格式、ledger、accounts db 或 geyser ABI 相关变更。

建议优先查看：

- Jito Solana release: `https://github.com/jito-foundation/jito-solana/releases`
- Yellowstone gRPC release: `https://github.com/rpcpool/yellowstone-grpc/releases`
- Agave upstream release: `https://github.com/anza-xyz/agave/releases`

## 版本匹配原则

validator 和 Yellowstone gRPC 必须按版本线匹配。

示例：

```text
Jito Solana v4.1.x-jito
Yellowstone gRPC *+solana.4.1.x 或至少 *+solana.4.1.0
```

如果 Yellowstone 没有完全对应的 patch 版本，例如没有 `solana.4.1.1`，可以使用同一 minor 线中明确发布的版本，例如 `v14.1.0+solana.4.1.0`。但要在文档中记录这个选择，并在启动后重点观察 geyser 插件日志。

不要使用这种组合：

```text
validator: v4.1.x-jito
geyser:   *+solana.4.0.x
```

这种组合存在 ABI 不兼容风险。

## 修改安装脚本

每次升级前，检查并修改 `2-install-jito-validator.sh` 顶部的版本配置。

需要关注这些变量：

```bash
DEFAULT_SOLANA_VERSION="vX.Y.Z"

YELLOWSTONE_RELEASE_TAG="..."
YELLOWSTONE_RELEASE_URL="..."
YELLOWSTONE_GEYSER_SO_URL="$YELLOWSTONE_RELEASE_URL/libyellowstone_grpc_geyser.so"
YELLOWSTONE_GEYSER_SO_SHA256="..."
```

同时建议更新脚本中的默认版本提示文案，避免执行时误以为默认还是旧版本。

如果只是临时升级，也可以不改 `DEFAULT_SOLANA_VERSION`，在脚本提示时手动输入目标版本。但 Yellowstone 相关变量必须改成目标版本线对应的 release。

## 升级步骤

进入服务器：

```bash
sudo su -
cd /root/solana-rpc-install
```

备份关键文件：

```bash
cp -a /root/sol/bin/validator-keypair.json /root/validator-keypair.json.bak.$(date +%F-%H%M)
cp -a /root/sol/bin/yellowstone-config.json /root/yellowstone-config.json.bak.$(date +%F-%H%M)
cp -a /etc/systemd/system/sol.service /root/sol.service.bak.$(date +%F-%H%M) 2>/dev/null || true
```

记录当前版本：

```bash
source /etc/profile.d/solana.sh 2>/dev/null || true
agave-validator --version || solana-validator --version || true
sha256sum /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so 2>/dev/null || true
```

停止服务：

```bash
systemctl stop sol
```

编译并安装目标版本：

```bash
bash 2-install-jito-validator.sh
```

脚本提示版本时，输入不带 `-jito` 后缀的版本号：

```text
vX.Y.Z
```

确认 validator 版本：

```bash
source /etc/profile.d/solana.sh
agave-validator --version || solana-validator --version
```

确认 Yellowstone 插件 SHA256：

```bash
sha256sum /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so
```

重新拉快照并启动：

```bash
bash 3-start.sh
```

## 启动后验证

查看 systemd 状态：

```bash
systemctl status sol --no-pager -l
```

查看实时日志：

```bash
journalctl -u sol -f
```

查看 validator 日志：

```bash
tail -f /root/solana-rpc.log
```

检查 RPC 健康状态：

```bash
/root/get_health.sh
```

检查追块状态：

```bash
/root/catchup.sh
```

重点观察：

- validator 是否成功启动。
- 是否成功加载 `libyellowstone_grpc_geyser.so`。
- 日志中是否出现 geyser ABI、accounts db、snapshot 解压或启动参数错误。
- RPC `getHealth` 是否恢复。
- 追块延迟是否持续下降。
- 内存是否超过当前机器对应 tier 的预期范围。

## 回滚流程

如果升级后无法稳定启动：

1. 先看日志：

```bash
journalctl -u sol -n 300 --no-pager -l
tail -n 300 /root/solana-rpc.log
```

2. 如果是 Yellowstone 插件问题，确认下载 URL 和 SHA256 是否正确。

3. 如果需要回退 validator，修改 `2-install-jito-validator.sh` 中的版本和 Yellowstone 变量为旧版本组合。

4. 重新安装旧版本：

```bash
systemctl stop sol
bash 2-install-jito-validator.sh
bash 3-start.sh
```

回滚也建议重新拉快照，因为旧 ledger/accounts 可能已经被新版本写入过，直接复用风险更高。

## 常见注意事项

- 不要在升级过程中执行 `1-prepare.sh`。
- `3-start.sh` 会清空 `/root/sol/ledger`、`/root/sol/accounts`、`/root/sol/snapshot`，这是预期行为。
- 如果 `yellowstone-config.json` 在生产环境中有自定义过滤器、token、监听地址或限流配置，升级前必须备份并手工合并。
- 如果服务器对公网开放 `8899`、`8900`、`10900`，建议用防火墙限制可信 IP。
- 如果新版本启动参数发生变化，需要同步更新 `validator-128g.sh`、`validator-192g.sh`、`validator-256g.sh`、`validator-512g.sh`。

## 本次升级：v4.1.1-jito

本次目标：

- Jito Solana: `v4.1.1-jito`
- 脚本输入版本: `v4.1.1`
- Yellowstone gRPC: `v14.1.0+solana.4.1.0`
- Geyser 插件: `libyellowstone_grpc_geyser.so`

Yellowstone gRPC 下载地址：

```text
https://github.com/rpcpool/yellowstone-grpc/releases/download/v14.1.0%2Bsolana.4.1.0/libyellowstone_grpc_geyser.so
```

SHA256：

```text
f15b654c930963016c5ace2052a72acca5bb64b2e8a630fcf15dbd41ca579eda
```

本次需要把 `2-install-jito-validator.sh` 中的相关配置改成：

```bash
DEFAULT_SOLANA_VERSION="v4.1.1"

YELLOWSTONE_RELEASE_TAG="v14.1.0+solana.4.1.0"
YELLOWSTONE_RELEASE_URL="https://github.com/rpcpool/yellowstone-grpc/releases/download/v14.1.0%2Bsolana.4.1.0"
YELLOWSTONE_GEYSER_SO_URL="$YELLOWSTONE_RELEASE_URL/libyellowstone_grpc_geyser.so"
YELLOWSTONE_GEYSER_SO_SHA256="f15b654c930963016c5ace2052a72acca5bb64b2e8a630fcf15dbd41ca579eda"
```

执行顺序：

```bash
sudo su -
cd /root/solana-rpc-install

cp -a /root/sol/bin/validator-keypair.json /root/validator-keypair.json.bak.$(date +%F-%H%M)
cp -a /root/sol/bin/yellowstone-config.json /root/yellowstone-config.json.bak.$(date +%F-%H%M)

systemctl stop sol

bash 2-install-jito-validator.sh
# 输入 v4.1.1

source /etc/profile.d/solana.sh
agave-validator --version || solana-validator --version
sha256sum /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so

bash 3-start.sh
```

截至 2026-07-08，rpcpool/yellowstone-grpc release 列表中没有单独的 `solana.4.1.1` release，因此本次使用同一 4.1 版本线的 `v14.1.0+solana.4.1.0`。
