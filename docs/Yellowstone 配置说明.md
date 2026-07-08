# Yellowstone 配置说明

本文说明本项目中的 `yellowstone-config.json` 配置项含义、常见修改方式和运维注意事项。

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

### address

示例：

```json
"address": "0.0.0.0:10900"
```

含义：

- `0.0.0.0` 表示监听所有网卡。
- `127.0.0.1` 表示只允许本机访问。
- `10900` 是监听端口。

本项目安装脚本默认放行的是 `10900/tcp`。如果配置为其他端口，例如 `10001`，需要同步调整 UFW 和云厂商安全组。

公网生产环境不建议无保护地监听 `0.0.0.0`。如果只有本机程序使用，建议改成：

```json
"address": "127.0.0.1:10900"
```

如果业务程序在其他服务器上，建议保留 `0.0.0.0`，但用 UFW 或云安全组只允许可信 IP 访问。

### x_token

示例：

```json
"x_token": "replace-with-a-long-random-token"
```

`x_token` 是 Yellowstone gRPC 的简单访问令牌。客户端连接时需要带上对应 token。

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
"max_decoding_message_size": "134_217_728"
```

这是服务端允许解码的客户端单个 gRPC 请求消息最大大小。`134_217_728` 等于 128 MiB。

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

如果删除了 `filters` 限制，并允许客户端提交较大的订阅请求，可以设置为 `67_108_864` 或 `134_217_728`。

### snapshot_plugin_channel_capacity

示例：

```json
"snapshot_plugin_channel_capacity": null
```

这个配置影响 snapshot 阶段插件内部通道容量。`null` 表示使用插件默认行为。

生产环境通常保持 `null`，除非你明确知道启动阶段 snapshot account replay 对内存和队列的影响，并且需要针对特殊负载调优。

### snapshot_client_channel_capacity

示例：

```json
"snapshot_client_channel_capacity": "50_000_000"
```

这个配置影响 snapshot 相关数据发送给客户端时的通道容量。数值越大，越能缓冲突发数据，但也可能增加内存占用。

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

自用节点通常 `1000` 足够。对外服务时可以结合业务压力和 CPU 使用情况调整。

### unary_disabled

示例：

```json
"unary_disabled": false
```

控制是否禁用 unary gRPC 方法。

- `false`：启用 unary 方法。
- `true`：禁用 unary 方法。

自用节点建议保持：

```json
"unary_disabled": false
```

## filters 配置

`grpc.filters` 是客户端订阅过滤器限制，不是 validator 同步数据限制。

如果配置了 `filters`，它会限制客户端可以如何订阅 Yellowstone 数据流，例如：

- 是否允许全量 accounts。
- 是否允许全量 transactions。
- 每类订阅最多允许多少个 filter。
- 是否禁止订阅某些热门 program，例如 SPL Token Program。
- block 订阅是否允许包含 transactions、accounts、entries。

如果省略整个 `filters` 字段，Yellowstone 默认不限制客户端过滤器。默认行为等价于：

- `any = true`
- `max = usize::MAX`
- reject 列表为空
- block 默认允许 transactions、accounts、entries

自用节点、可信客户端、需要完整数据流时，建议直接删除整个 `filters` 字段。

示例：

```json
{
  "grpc": {
    "address": "0.0.0.0:10900",
    "x_token": "replace-with-a-long-random-token",
    "compression": {
      "accept": ["gzip", "zstd"],
      "send": ["gzip", "zstd"]
    },
    "max_decoding_message_size": "134_217_728",
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
- `max_decoding_message_size` 设置为 `67_108_864` 或 `134_217_728`。
- `compression` 保留 `gzip` 和 `zstd`。
- `channel_capacity` 根据内存和客户端消费速度调整。
- `address`、UFW、云安全组端口保持一致。

示例：

```json
{
  "libpath": "/root/sol/bin/yellowstone-grpc-geyser-release/lib/libyellowstone_grpc_geyser.so",
  "log": {
    "level": "info"
  },
  "grpc": {
    "address": "0.0.0.0:10900",
    "x_token": "replace-with-a-long-random-token",
    "compression": {
      "accept": ["gzip", "zstd"],
      "send": ["gzip", "zstd"]
    },
    "max_decoding_message_size": "134_217_728",
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
sudo ufw allow from <your-client-ip> to any port 10900 proto tcp
sudo ufw deny 10900/tcp
sudo ufw status
```

如果已经存在宽松规则，例如 `sudo ufw allow 10900`，需要按实际情况删除旧规则后再添加来源 IP 限制。

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
