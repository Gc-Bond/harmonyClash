# harmonyClash

面向 HarmonyOS NEXT 的开源 Clash 客户端：**界面用 ArkUI 原生**，内核基于 mihomo（Clash Meta）。

## 协作方式

- 用户只看结果：不用先汇报方案等确认，直接推进，可以并行开多个 agent；只在必须由用户本人操作（手机上点授权、DevEco 界面操作）时打断。
- 需求、决策、进度、踩过的坑都要随手写进 `docs/` 下对应的文件，本文件只做大纲和索引。

## 文档索引

| 文件 | 内容 | 什么时候更新 |
|---|---|---|
| [docs/requirements.md](docs/requirements.md) | 需求、功能清单及状态、非目标 | 需求变化、功能状态变化 |
| [docs/architecture.md](docs/architecture.md) | 进程架构、决策记录、内核接口要点 | 做出设计决策时 |
| [docs/dev-guide.md](docs/dev-guide.md) | 本机环境、内核编译、构建安装调试命令、踩过的坑 | 环境/流程变化、踩坑后 |
| [docs/changelog.md](docs/changelog.md) | 按日期的进度和变更 | 每完成一块工作 |

## 工程结构

仓库根目录就是 DevEco 工程，包名 `com.gc.harmonyclash`：

- `core/`：HAR 模块，N-API 封装（`napi_init.cpp` 照搬 FlClash-ohos，GPL-3.0），链接 `libs/arm64-v8a/libclash.so`（gitignore，编法见 dev-guide）。
- `entry/`：应用主模块。
  - `ets/vpn/`：VpnExtAbility（内核运行处）和界面侧 VpnClient。
  - `ets/api/`：mihomo REST API 客户端。
  - `ets/profile/`：订阅管理和运行配置 `config.yaml` 生成。
  - `ets/pages/`：界面。
- `ref/FlClash-ohos/`：参考项目（gitignore）。
- `build/`：内核编译产物（gitignore）。

## 路线

1. ~~验证内核：交叉编译 `libclash.so`，真机上跑起来~~（已完成）
2. ~~VpnExtAbility + TUN，REST 客户端，订阅/配置模块~~（已在真机验证；包名识别限制见 changelog）
3. ArkUI 界面（已重排仪表盘、代理和配置页，加入真实流量统计、离线节点目录与应用图标；当前版本已构建并在真机核对主要交互，后续继续打磨）
