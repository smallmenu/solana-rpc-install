# Solana 升级指导

本文档是本项目的通用升级 Runbook，适用于后续 Solana / Jito Solana / Yellowstone gRPC 的较大版本升级。

核心原则：

- `1-prepare.sh` 只用于首次部署和磁盘初始化，升级时不要执行。
- `2-install-jito-validator.sh` 用于编译并安装目标版本的 Jito Solana validator。
- `3-start.sh` 默认清理 `ledger/accounts/accounts_index/snapshot`，重新下载快照并启动节点；只有明确使用 `--keep-data` 才会复用本地数据。
- 本项目运维策略是：较大升级或重启后，优先重新拉快照启动，避免从旧 ledger 长时间追块但追不上。
- Yellowstone gRPC 的 `libyellowstone_grpc_geyser.so` 需要和 Solana/Agave/Jito Solana 版本线匹配，不能只升级 validator 而继续使用旧版本 geyser 插件。
- 当前生产环境的 Yellowstone 插件由 `yellowstone-grpc` 生产分支自行构建，安装脚本固定从 `/data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so` 安装，不使用官方 release 二进制。

## 升级前确认

每次升级前先确认这些信息：

- 目标 Jito Solana tag，例如 `v4.2.1-jito`。
- 输入脚本时使用的版本号，例如 `v4.2.1`，不要带 `-jito` 后缀。
- 对应 Yellowstone gRPC upstream tag、生产分支和准确 commit。
- 自行构建的 `libyellowstone_grpc_geyser.so` 是否已经生成到安装脚本固定路径。
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
Jito Solana v4.2.x-jito
Yellowstone gRPC *+solana.4.2.x 或至少 *+solana.4.2.0
```

如果 Yellowstone 没有完全对应的 patch 版本，可以使用同一 Solana minor 线的 upstream 基线自行构建。但要在文档中记录生产分支和准确 commit，并在启动后重点观察 geyser 插件日志。

不要使用这种组合：

```text
validator: v4.2.x-jito
geyser:   *+solana.4.1.x
```

这种组合存在 ABI 不兼容风险。

## 修改安装脚本

每次升级前，检查并修改 `2-install-jito-validator.sh` 顶部的版本配置。

需要关注这些变量：

```bash
DEFAULT_SOLANA_VERSION="vX.Y.Z"
YELLOWSTONE_GEYSER_SOURCE="/data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so"
YELLOWSTONE_CUSTOM_BUILD_REF="branch@commit"
```

生产升级前必须先把自构建产物生成到固定路径：

```bash
test -f /data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so
```

脚本不检查 SHA256，也不会自动下载官方备用插件。固定路径不存在时会在编译 validator 前终止。

同时建议更新脚本中的默认版本提示文案，避免执行时误以为默认还是旧版本。

如果只是临时升级，也可以不改 `DEFAULT_SOLANA_VERSION`，在脚本提示时手动输入目标版本。但 Yellowstone 固定路径中的产物必须与目标 Solana 版本线兼容。

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
test -f /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so || true
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
agave-validator --version
```

确认 Yellowstone 插件已经安装：

```bash
test -f /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so
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

2. 如果是 Yellowstone 插件问题，确认固定路径中的构建产物来自正确的生产分支和 commit。

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
- `3-start.sh` 默认会清空 `/root/sol/ledger`、`/root/sol/accounts`、`/root/sol/accounts_index`、`/root/sol/snapshot`，执行前需要输入 `FRESH-SYNC` 确认；`3-start.sh --keep-data` 才会复用本地数据。
- 如果 `yellowstone-config.json` 在生产环境中有自定义过滤器、token、监听地址或限流配置，升级前必须备份并手工合并。
- `update-runtime.sh` 和 `3-start.sh` 不会覆盖 `/root/sol/bin/yellowstone-config.json`。完整安装脚本 `2-install-jito-validator.sh` 现在也会备份并保留已有配置，只在配置不存在时安装仓库模板；新版字段仍需手工合并并验证。
- 如果服务器对公网开放 `8899`、`8900`、`10001`，建议用防火墙限制可信 IP。
- 如果新版本启动参数发生变化，需要同步更新 `validator-128g.sh`、`validator-192g.sh`、`validator-256g.sh`、`validator-512g.sh`。

## 本次升级：v4.2.1-jito

> 当前生产环境使用 `yellowstone-grpc` 仓库生产分支自行构建的产物。`2-install-jito-validator.sh` 固定从 `/data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so` 安装，不再保留官方 release 自动 fallback。

本次目标：

- Jito Solana: `v4.2.1-jito`
- Jito annotated tag object: `001679b24964b7bda9a586729695555ed7e1cbf1`
- Jito source commit: `166de6d3a5082ce1abbe04dd42077fa75cac877e`
- 脚本输入版本: `v4.2.1`
- Yellowstone gRPC upstream 基线: `v15.0.1+solana.4.2.0`
- Yellowstone gRPC 生产构建分支: `sm-v15.1.0-v4.2.0`
- Yellowstone gRPC 生产 commit: `58d94ff3a4c77fb37e0f637e82b7b0b7eee3607c`
- Geyser 插件: `libyellowstone_grpc_geyser.so`

本次需要把 `2-install-jito-validator.sh` 中的相关配置改成：

```bash
DEFAULT_SOLANA_VERSION="v4.2.1"
YELLOWSTONE_GEYSER_SOURCE="/data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so"
YELLOWSTONE_CUSTOM_BUILD_REF="sm-v15.1.0-v4.2.0@58d94ff"
```

生产升级前，在 Linux 构建自定义插件：

```bash
cd /data/yellowstone-grpc
git switch sm-v15.1.0-v4.2.0
git rev-parse HEAD
cargo build --release -p yellowstone-grpc-geyser
test -f /data/yellowstone-grpc/target/release/libyellowstone_grpc_geyser.so
```

执行顺序：

```bash
sudo su -
cd /root/solana-rpc-install

cp -a /root/sol/bin/validator-keypair.json /root/validator-keypair.json.bak.$(date +%F-%H%M)
cp -a /root/sol/bin/yellowstone-config.json /root/yellowstone-config.json.bak.$(date +%F-%H%M)

systemctl stop sol

bash 2-install-jito-validator.sh
# 直接回车使用 v4.2.1

source /etc/profile.d/solana.sh
agave-validator --version || solana-validator --version
test -f /root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so
jq -e '.grpc.static_owner_allowlist | type == "array" and length > 0' \
  /root/sol/bin/yellowstone-config.json

bash 3-start.sh
```

安装脚本会在 `/root/sol/bin/yellowstone-backups/<timestamp>-<random>/` 备份原插件和配置，并保留已有 `/root/sol/bin/yellowstone-config.json`。首次安装或现有配置没有 allowlist 时，需要在启动前手工合并生产 `static_owner_allowlist`。

已对 `v4.2.1-jito` 源码核对 validator CLI。其 validator CLI 核心文件与 `v4.2.0-jito` 完全一致：Linux 默认尝试启用 XDP，`--no-xdp` 用于回退到 UDP sockets，同时 `--allow-private-addr` 明确要求 `--no-xdp`。因此四个 validator tier 脚本继续保留 `--no-xdp`，其余已有 CLI 参数未发现需要删除或改名。

截至本次记录，生产环境以 `v15.0.1+solana.4.2.0` 为 upstream 基线，在 `sm-v15.1.0-v4.2.0` 分支保留 `static_owner_allowlist` 定制并自行构建。安装脚本只使用固定路径中的自构建产物，不使用官方 release 二进制，也不检查 SHA256。
