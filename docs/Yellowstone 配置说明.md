# Yellowstone 配置说明

本文说明本项目中的 `yellowstone-config.json` 配置项含义、常见修改方式和运维注意事项。

当前生产环境使用 `yellowstone-grpc` 生产分支自行构建的 `libyellowstone_grpc_geyser.so`。本文配置值以仓库当前模板为准；安装脚本下载的官方 release 二进制只作为备用路径。

## 文件位置

仓库中的模板文件：

```text
yellowstone-config.json
```

安装后的实际生效文件：

```text
/root/sol/bin/yellowstone-config.json
```

`2-install-jito-validator.sh` 会把仓库里的模板复制到 `/root/sol/bin/yellowstone-config.json`。如果节点已经安装完成，后续只修改仓库模板不会自动影响正在运行的节点，需要同步修改服务器上的实际生效文件。

validator 启动参数中通过下面的参数加载 Yellowstone Geyser 插件配置：

```bash
--geyser-plugin-config /root/sol/bin/yellowstone-config.json
```

修改配置后需要重启 `sol.service` 才会生效：

```bash
sudo systemctl restart sol.service
sudo journalctl -u sol.service -f
```

## 推荐修改流程

修改生产配置前先备份：

```bash
sudo cp -a /root/sol/bin/yellowstone-config.json /root/sol/bin/yellowstone-config.json.bak.$(date +%F-%H%M)
sudo nano /root/sol/bin/yellowstone-config.json
sudo systemctl restart sol.service
sudo journalctl -u sol.service -f
```

`yellowstone-config.json` 是 JSON 文件，不能写注释，字符串和逗号也必须符合 JSON 语法。

## 顶层配置

示例：

```json
{
  "libpath": "/root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so",
  "log": {
    "level": "info"
  },
  "grpc": {}
}
```

### libpath

`libpath` 是 Yellowstone Geyser 插件动态库路径。

```json
"libpath": "/root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so"
```

这个 `.so` 文件必须和当前 Solana / Agave / Jito Solana 的版本线匹配。升级 validator 时需要同时确认 Yellowstone gRPC release 是否匹配，否则可能出现 Geyser ABI 不兼容、插件加载失败或运行时异常。

### log.level

`log.level` 控制 Yellowstone 插件日志级别。

常用值：

```text
error
warn
info
debug
trace
```

生产环境建议使用：

```json
"log": {
  "level": "info"
}
```

排查问题时可以临时改成 `debug`，但日志量会明显增加。

## grpc 配置

`grpc` 是 Yellowstone gRPC 服务端配置，控制监听地址、鉴权、压缩、消息大小、队列容量、并发和订阅限制。

### 源码默认值来源

以下默认值参考本地源码：

```text
D:\Repos\solana-rpc\yellowstone-grpc
branch: master
commit: 919b411
```

主要源码位置：

```text
yellowstone-grpc-geyser/src/config.rs
yellowstone-grpc-geyser/src/plugin/filter/limits.rs
yellowstone-grpc-geyser/src/grpc.rs
yellowstone-grpc-tools/src/server/tonic/metered.rs
```

注意：源码默认值表示“配置文件没有写这个字段时”的行为。本项目模板通常会显式写入一部分字段，因此实际运行值以 `/root/sol/bin/yellowstone-config.json` 为准。

### grpc 源码默认值总览

| 字段 | 源码默认值 | 当前模板值 / 生产建议 | 说明 |
|------|------------|-------------------|------|
| `address` | `null` / 未设置 | 不设置 | 旧式顶层监听字段，已弃用。 |
| `listen` | `null` | 当前模板监听 `0.0.0.0:10001` | 新式监听配置，支持多个地址、TLS 和 per-listener auth；端口必须和 UFW、安全组及客户端一致。 |
| `tls_config` | `null` | 通常不设置 | 旧式 TLS 配置，upstream README 建议用 `listen[].tls`。 |
| `cert_dir` | `null` | 通常不设置 | TLS 证书目录。 |
| `x_token` | `null` | 当前模板 `""`；生产必须替换为强随机 token | 空字符串不是 `null`，仍会启用 token 比对。 |
| `compression.accept` | `["gzip", "zstd"]` | `["gzip", "zstd"]` | 服务端接受客户端请求压缩格式。 |
| `compression.send` | `["gzip", "zstd"]` | `["gzip", "zstd"]` | 服务端发送给客户端时可用压缩格式。 |
| `max_decoding_message_size` | `4_194_304` | 当前模板 `536_870_912` | 客户端单个请求消息的最大解码大小；当前模板为 512 MiB。 |
| `snapshot_plugin_channel_capacity` | `null` | `null` | 设置后 snapshot account replay 会使用 bounded channel；满了会阻塞 validator startup。 |
| `snapshot_client_channel_capacity` | `50_000_000` | `50_000_000` | snapshot 数据发送给客户端的通道容量。 |
| `channel_capacity` | `250_000` | 自用可提高，例如 `2_000_000` | 每个连接的广播通道容量。 |
| `unary_concurrency_limit` | `Semaphore::MAX_PERMITS` | `1000` | unary 方法并发限制。源码默认极大，模板显式收敛。 |
| `unary_disabled` | `false` | `false` | 是否禁用 unary gRPC 方法。 |
| `subscription_limit` | `1000` | 默认即可 | 每个 subscriber ID 的并发订阅数上限。 |
| `subscription_limit_enforce` | `false` | 默认即可 | 默认只记录和打指标，不直接拒绝；设为 `true` 才强制拒绝。 |
| `filter_limits` / `filters` | 各类 filter 基本无限制 | 自用建议省略 | `filters` 是 `filter_limits` 的别名。省略时使用源码默认值。 |
| `filter_name_size_limit` | `128` | 默认即可 | 单个 filter 名称长度限制。 |
| `filter_names_size_limit` | `4_096` | 默认即可 | filter 名称缓存数量，到达后触发清理。 |
| `filter_names_cleanup_interval` | `1s` | 默认即可 | filter 名称清理间隔。 |
| `replay_stored_slots` | `150` | 默认即可 | replay/auto-reconnect 可回放的 slot 数。设置为 `0` 会关闭 replay buffer。 |
| `server_http2_adaptive_window` | `null` | 默认即可 | HTTP/2 自适应窗口，交给 tonic 默认行为。 |
| `server_http2_keepalive_interval` | `null` | 默认即可 | HTTP/2 keepalive interval。 |
| `server_http2_keepalive_timeout` | `null` | 默认即可 | HTTP/2 keepalive timeout。 |
| `server_initial_connection_window_size` | `null` | 默认即可 | HTTP/2 connection window 初始大小。 |
| `server_initial_stream_window_size` | `null` | 默认即可 | HTTP/2 stream window 初始大小。 |
| `traffic_reporting_byte_threhsold` | 配置默认 `null`，运行时使用 `32 KiB` | 默认即可 | 源码字段名拼写为 `threhsold`。运行时默认来自 `DEFAULT_TRAFFIC_REPORTING_THRESHOLD`。 |
| `ip_conncur_rate_limit` | `u64::MAX` | 自用默认即可 | 每个远端 IP 最大并发连接数，默认等价于不限制。 |
| `listen[].auth` | `null` | 可选 | 新式 listener 认证层，不配置则不启用这层认证。 |
| `listen[].auth.ratelimit` | `null` | 可选 | 方法级限流，不配置则不启用方法级 ratelimit。 |

`usize::MAX` / `u64::MAX` 在这些限制项里基本表示“不限制”。在 64 位 Linux 上，`usize::MAX` 是 `18_446_744_073_709_551_615`。

### listen

示例：

```json
"listen": [
  {
    "address": "0.0.0.0:10001"
  }
]
```

含义：

- `0.0.0.0` 表示监听所有网卡。
- `127.0.0.1` 表示只允许本机访问。
- `10001` 是当前模板监听端口。

本项目当前配置模板监听 `10001/tcp`，但安装脚本仍默认放行 `10900/tcp`。生产部署时必须同步调整 UFW、云厂商安全组和客户端连接地址。

源码默认值：`listen` 是 `Option`，不写时为 `null`。旧的顶层 `grpc.address` 已弃用，当前模板使用 upstream 推荐的 `grpc.listen` 数组。

公网生产环境不建议无保护地监听 `0.0.0.0`。如果只有本机程序使用，建议改成：

```json
"listen": [
  {
    "address": "127.0.0.1:10001"
  }
]
```

如果业务程序在其他服务器上，建议保留 `0.0.0.0`，但用 UFW 或云安全组只允许可信 IP 访问。

### x_token

当前模板：

```json
"x_token": ""
```

空字符串会作为实际 token 参与校验，并不等价于 `null` 或省略字段。客户端不携带对应的空 token 时仍会鉴权失败；由于该值完全可预测，不能用于生产保护。

生产建议：

```json
"x_token": "replace-with-a-long-random-token"
```

`x_token` 是 Yellowstone gRPC 的简单访问令牌。客户端连接时需要带上对应 token。

源码默认值：`null`。也就是说，如果配置文件不写 `x_token`，就没有这个简单 token 校验。

建议：

- 不要使用默认值或容易猜到的字符串。
- 使用足够长的随机 token。
- 不要把 gRPC 端口对公网裸开。

生成随机 token 示例：

```bash
openssl rand -hex 32
```

### compression

示例：

```json
"compression": {
  "accept": ["gzip", "zstd"],
  "send": ["gzip", "zstd"]
}
```

含义：

- `accept`：服务端允许客户端发来的请求使用哪些压缩格式。
- `send`：服务端向客户端推送数据时允许使用哪些压缩格式。
- `gzip`：兼容性好。
- `zstd`：通常压缩率和性能更好，但客户端也必须支持。

远程公网传输全量 transactions 或 accounts 时，压缩通常有价值，可以降低带宽占用。本机或同机房内网使用时，压缩收益较小，并且会增加 CPU 消耗。

源码默认值：`accept` 和 `send` 都是 `["gzip", "zstd"]`。如果配置文件省略整个 `compression` 字段，仍会启用这两个压缩格式。

一般建议保留：

```json
"compression": {
  "accept": ["gzip", "zstd"],
  "send": ["gzip", "zstd"]
}
```

### max_decoding_message_size

示例：

```json
"max_decoding_message_size": "536_870_912"
```

这是服务端允许解码的客户端单个 gRPC 请求消息最大大小。当前模板的 `536_870_912` 等于 512 MiB。

源码默认值：`4_194_304`，即 4 MiB。本项目模板通常会显式提高这个值，避免大型订阅请求被默认上限拒绝。

这个配置主要影响客户端发来的订阅请求，例如：

- 很多 `account_include`
- 很多 `account_required`
- 很多 account pubkey
- 很大的 memcmp filter
- 很复杂的 `SubscribeRequest`

它不是服务端向客户端推送数据的大小限制。服务端向外推送数据主要受网络、CPU、客户端消费速度、`channel_capacity` 等因素影响。

常用值：

```text
4 MiB     = 4_194_304
8 MiB     = 8_388_608
16 MiB    = 16_777_216
32 MiB    = 33_554_432
64 MiB    = 67_108_864
128 MiB   = 134_217_728
256 MiB   = 268_435_456
512 MiB   = 536_870_912
1024 MiB  = 1_073_741_824
```

当前代码口径使用 `536_870_912`。如果实际订阅请求远小于 512 MiB，可以在压测后降低到 `67_108_864` 或 `134_217_728`，减少异常大请求带来的内存压力。

### snapshot_plugin_channel_capacity

示例：

```json
"snapshot_plugin_channel_capacity": null
```

这个配置影响 snapshot 阶段插件内部通道容量。`null` 表示使用插件默认行为。

源码默认值：`null`。源码逻辑是：只有设置为具体数值且不是 reload 场景时，才创建 bounded snapshot channel；否则不创建这个 snapshot channel。设置过小可能导致 snapshot replay 阶段阻塞 validator startup。

生产环境通常保持 `null`，除非你明确知道启动阶段 snapshot account replay 对内存和队列的影响，并且需要针对特殊负载调优。

### snapshot_client_channel_capacity

示例：

```json
"snapshot_client_channel_capacity": "50_000_000"
```

这个配置影响 snapshot 相关数据发送给客户端时的通道容量。数值越大，越能缓冲突发数据，但也可能增加内存占用。

源码默认值：`50_000_000`。

通常可以保留默认值：

```json
"snapshot_client_channel_capacity": "50_000_000"
```

### channel_capacity

示例：

```json
"channel_capacity": "2_000_000"
```

`channel_capacity` 是每个连接的数据通道容量。客户端消费速度跟不上服务端推送速度时，这个容量决定可以缓冲多少消息。

源码默认值：`250_000`。本项目自用高吞吐场景可以提高，例如 `2_000_000`，但要评估慢客户端带来的内存占用。

取值影响：

- 数值越大，短时间突发流量更不容易丢失或断流。
- 数值越大，慢客户端占用的内存可能越高。
- 数值过小，全量订阅或高峰期更容易触发队列压力。

如果是自用节点，客户端数量少，并且机器内存充足，可以适当调大。如果对外提供服务，应该谨慎放大，避免单个慢客户端占用过多内存。

### unary_concurrency_limit

示例：

```json
"unary_concurrency_limit": 1000
```

限制 unary gRPC 请求的并发量。unary 请求是一次请求一次响应的接口，例如获取版本、slot、blockhash 等。

源码默认值：`tokio::sync::Semaphore::MAX_PERMITS`，这是一个非常大的值。模板里显式设置 `1000` 是为了给 unary 请求一个更可控的上限。

自用节点通常 `1000` 足够。对外服务时可以结合业务压力和 CPU 使用情况调整。

### unary_disabled

示例：

```json
"unary_disabled": false
```

控制是否禁用 unary gRPC 方法。

源码默认值：`false`。

- `false`：启用 unary 方法。
- `true`：禁用 unary 方法。

自用节点建议保持：

```json
"unary_disabled": false
```

### subscription_limit

示例：

```json
"subscription_limit": 1000
```

限制每个 subscriber ID 允许同时存在多少个订阅。subscriber ID 由 `x-subscription-id` header 识别；没有该 header 时会回退到远端 IP。

源码默认值：`1000`。

如果只给自己的少量客户端使用，通常不用显式配置。对外服务时可以调低，并配合 `subscription_limit_enforce`。

### subscription_limit_enforce

示例：

```json
"subscription_limit_enforce": true
```

控制超过 `subscription_limit` 时是否真正拒绝连接。

源码默认值：`false`。

- `false`：超过限制时记录日志和指标，但不拒绝。
- `true`：超过限制时返回 `RESOURCE_EXHAUSTED`。

对外服务建议设为 `true` 并设置合理的 `subscription_limit`。自用节点可以保持默认。

### filter_name_size_limit

示例：

```json
"filter_name_size_limit": 128
```

限制客户端订阅请求中单个 filter 名称的最大长度。

源码默认值：`128`。

### filter_names_size_limit

示例：

```json
"filter_names_size_limit": 4096
```

限制 filter 名称缓存数量。达到这个数量后，服务端会按 `filter_names_cleanup_interval` 尝试清理。

源码默认值：`4_096`。

### filter_names_cleanup_interval

示例：

```json
"filter_names_cleanup_interval": "1s"
```

filter 名称缓存清理间隔。

源码默认值：`1s`。

### replay_stored_slots

示例：

```json
"replay_stored_slots": 150
```

控制 Yellowstone 为 replay / auto-reconnect 保留多少个 slot 的数据。

源码默认值：`150`。源码里如果该值小于 `150` 会打印警告；如果设置为 `0`，会关闭 replay buffer。

自用节点通常保持默认即可。除非明确不需要 replay，才考虑设置为 `0`。

### HTTP/2 可选参数

这些参数通常不用配置，交给 tonic 默认行为即可：

```json
"server_http2_adaptive_window": null,
"server_http2_keepalive_interval": null,
"server_http2_keepalive_timeout": null,
"server_initial_connection_window_size": null,
"server_initial_stream_window_size": null
```

源码默认值全部是 `null`。

如果客户端经过负载均衡、代理或跨公网长连接容易被断开，可以考虑配置 keepalive，但需要结合客户端和中间网络设备一起测试。

### traffic_reporting_byte_threhsold

示例：

```json
"traffic_reporting_byte_threhsold": "32 KiB"
```

这个参数控制 gRPC 流量指标累计多少字节后更新一次 Prometheus 统计。

源码字段名拼写是 `traffic_reporting_byte_threhsold`，不是 `traffic_reporting_byte_threshold`。配置时必须按源码拼写。

源码配置默认值是 `null`；运行时如果为 `null`，会使用 `yellowstone-grpc-tools` 里的 `DEFAULT_TRAFFIC_REPORTING_THRESHOLD`，当前本地源码为 `32 KiB`。

一般不需要配置。

### ip_conncur_rate_limit

示例：

```json
"ip_conncur_rate_limit": 100
```

限制每个远端 IP 的最大并发连接数。

源码默认值：`u64::MAX`，等价于不限制。

自用节点一般不用设置。对外服务时可以设置具体值，配合防火墙、token、`filters` 和订阅限制一起使用。

### 多监听地址和 listener 配置

示例：

```json
"listen": [
  {
    "address": "0.0.0.0:10001"
  }
]
```

`listen` 是 upstream README 推荐的新式监听配置，支持多个监听地址，并且可以给不同 listener 配置不同 TLS/auth。

源码默认值：`null`。

本项目模板已迁移到 `listen`。如果需要更复杂的 TLS 或认证配置，可以继续在每个 listener 中分别配置。

### listen[].auth

`listen[].auth` 是新式 listener 的认证配置，和旧式全局 `x_token` 不是同一个东西。

源码默认值：`null`。不配置 `auth` 时，不启用这层认证。

支持的认证类型：

- `http`：请求外部 HTTP resolver 校验订阅。
- `file`：读取本地 JSON 文件做 token/host 映射。
- `trusted-metadata`：信任请求里的 `x-subscription-id`，不做外部认证。

`http` auth 的源码默认值：

| 字段 | 源码默认值 | 说明 |
|------|------------|------|
| `subscription_resolution_cache_ttl` | `null` | 默认不缓存 resolver 结果。 |
| `max_concurrent_auth_requests` | `1000` | 最大并发认证请求数。 |
| `forwarded_headers` | `["x-token"]` | 转发给 resolver 的 header 列表。 |

`auth.ratelimit` 的源码默认值：

| 字段 | 源码默认值 | 说明 |
|------|------------|------|
| `ratelimit` | `null` | 不配置时不启用方法级 ratelimit。 |
| `ratelimit.default_max_hits` | `1000` | 启用 ratelimit 后，默认窗口内最大请求数。负数表示不限制。 |
| `ratelimit.window` | `10s` | 默认限流窗口。 |

自用节点一般不需要 `listen[].auth`，使用 `x_token` 加防火墙限制来源 IP 更简单。对外服务或多租户场景可以考虑迁移到 `listen` + `auth`。

## filters 配置

`grpc.filters` 是客户端订阅过滤器限制，不是 validator 同步数据限制。

如果配置了 `filters`，它会限制客户端可以如何订阅 Yellowstone 数据流，例如：

- 是否允许全量 accounts。
- 是否允许全量 transactions。
- 每类订阅最多允许多少个 filter。
- 是否禁止订阅某些热门 program，例如 SPL Token Program。
- block 订阅是否允许包含 transactions、accounts、entries。

如果省略整个 `filters` 字段，Yellowstone 默认不限制客户端过滤器。默认行为等价于：

- `max = usize::MAX`
- `any = true`
- 各类 pubkey 数量上限为 `usize::MAX`
- reject 列表为空
- block 默认允许 `transactions`、`accounts`、`entries`

源码中字段名是 `filter_limits`，同时通过 serde alias 兼容 `filters`。也就是说下面两个名字表达的是同一个配置：

```json
"filter_limits": {}
```

```json
"filters": {}
```

### filters 源码默认值明细

| 分类 | 字段 | 源码默认值 |
|------|------|------------|
| `accounts` | `max` | `usize::MAX` |
| `accounts` | `any` | `true` |
| `accounts` | `account_max` | `usize::MAX` |
| `accounts` | `account_reject` | `[]` |
| `accounts` | `owner_max` | `usize::MAX` |
| `accounts` | `owner_reject` | `[]` |
| `accounts` | `data_slice_max` | `usize::MAX` |
| `accounts` | `cuckoo_max_size` | `usize::MAX` |
| `slots` | `max` | `usize::MAX` |
| `transactions` | `max` | `usize::MAX` |
| `transactions` | `any` | `true` |
| `transactions` | `account_include_max` | `usize::MAX` |
| `transactions` | `account_include_reject` | `[]` |
| `transactions` | `account_exclude_max` | `usize::MAX` |
| `transactions` | `account_required_max` | `usize::MAX` |
| `transactions_status` | 同 `transactions` | 同 `transactions` |
| `blocks` | `max` | `usize::MAX` |
| `blocks` | `account_include_max` | `usize::MAX` |
| `blocks` | `account_include_any` | `true` |
| `blocks` | `account_include_reject` | `[]` |
| `blocks` | `include_transactions` | `true` |
| `blocks` | `include_accounts` | `true` |
| `blocks` | `include_entries` | `true` |
| `blocks` | `cuckoo_max_size` | `usize::MAX` |
| `blocks_meta` | `max` | `usize::MAX` |
| `entries` | `max` | `usize::MAX` |
| `deshred_transactions` | `max` | `usize::MAX` |
| `deshred_transactions` | `any` | `true` |
| `deshred_transactions` | `account_include_max` | `usize::MAX` |
| `deshred_transactions` | `account_include_reject` | `[]` |
| `deshred_transactions` | `account_exclude_max` | `usize::MAX` |
| `deshred_transactions` | `account_required_max` | `usize::MAX` |

自用节点、可信客户端、需要完整数据流时，建议直接删除整个 `filters` 字段。

示例：

```json
{
  "grpc": {
    "listen": [
      {
        "address": "0.0.0.0:10001"
      }
    ],
    "x_token": "replace-with-a-long-random-token",
    "compression": {
      "accept": ["gzip", "zstd"],
      "send": ["gzip", "zstd"]
    },
    "max_decoding_message_size": "536_870_912",
    "snapshot_plugin_channel_capacity": null,
    "snapshot_client_channel_capacity": "50_000_000",
    "channel_capacity": "2_000_000",
    "unary_concurrency_limit": 1000,
    "unary_disabled": false
  }
}
```

如果对外提供公共服务，不建议完全删除 `filters`，否则客户端可以发起全量 accounts 或 full transaction stream，对 CPU、内存和带宽压力很大。

## 自用节点建议配置

如果只给自己的程序使用，并且已经通过防火墙限制访问 IP，可以使用下面的策略：

- 删除 `grpc.filters`。
- 保留 `x_token`，并换成随机强 token。
- 当前模板的 `max_decoding_message_size` 是 `536_870_912`；确认客户端请求规模后可以压测并收敛该上限。
- `compression` 保留 `gzip` 和 `zstd`。
- `channel_capacity` 根据内存和客户端消费速度调整。
- `listen[].address`、UFW、云安全组端口保持一致。

示例：

```json
{
  "libpath": "/root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so",
  "log": {
    "level": "info"
  },
  "grpc": {
    "listen": [
      {
        "address": "0.0.0.0:10001"
      }
    ],
    "x_token": "replace-with-a-long-random-token",
    "compression": {
      "accept": ["gzip", "zstd"],
      "send": ["gzip", "zstd"]
    },
    "max_decoding_message_size": "536_870_912",
    "snapshot_plugin_channel_capacity": null,
    "snapshot_client_channel_capacity": "50_000_000",
    "channel_capacity": "2_000_000",
    "unary_concurrency_limit": 1000,
    "unary_disabled": false
  }
}
```

## 安全建议

Yellowstone gRPC 可以输出高吞吐链上数据流，不应直接无限制暴露到公网。

最低建议：

- 使用强 `x_token`。
- UFW 只允许可信 IP 访问 gRPC 端口。
- 云厂商安全组同步限制来源 IP。
- 不对未知客户端开放无 `filters` 限制的全量订阅。

UFW 示例：

```bash
sudo ufw allow from <your-client-ip> to any port 10001 proto tcp
sudo ufw deny 10001/tcp
sudo ufw status
```

如果已经存在宽松规则，例如 `sudo ufw allow 10001`，需要按实际情况删除旧规则后再添加来源 IP 限制。安装脚本中的 `10900` 规则也需要同步清理或改成实际生产端口。

## 排查命令

查看服务日志：

```bash
sudo journalctl -u sol.service -f
```

确认监听端口：

```bash
sudo ss -lntp | grep -E '10900|10001'
```

确认配置文件内容：

```bash
sudo cat /root/sol/bin/yellowstone-config.json
```

确认防火墙状态：

```bash
sudo ufw status numbered
```

## 参考

- Yellowstone gRPC README: `https://github.com/rpcpool/yellowstone-grpc`
- Yellowstone gRPC filter limits 源码: `https://github.com/rpcpool/yellowstone-grpc/blob/master/yellowstone-grpc-geyser/src/plugin/filter/limits.rs`
- Yellowstone gRPC config 源码: `https://github.com/rpcpool/yellowstone-grpc/blob/master/yellowstone-grpc-geyser/src/config.rs`
