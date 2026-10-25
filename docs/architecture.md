# 架构与决策

## 总体

```
┌────────────── 界面进程（EntryAbility, ArkUI）──────────────┐
│ pages/…        ──REST (127.0.0.1:9090, Bearer secret)──┐   │
│ profile/ 订阅管理、生成 config.yaml                     │   │
│ vpn/VpnClient  ──IPC: start / stop / status──┐          │   │
└──────────────────────────────────────────────│──────────│───┘
┌────────────── VPN 扩展进程（VpnExtAbility）──▼──────────▼───┐
│ core(HAR, N-API: libcore.so) → libclash.so (mihomo, Go)      │
│ vpnConnection.create() 拿 fd → startTUN(fd)                  │
│ protect(socketFd) 让内核自身出站绕开 VPN                      │
└──────────────────────────────────────────────────────────────┘
```

## 决策记录

| 日期 | 决策 | 原因 |
|---|---|---|
| 2026-10-21 | 内核层照搬 FlClash-ohos：Go 内核 + N-API + VpnExtensionAbility | 已有可用实现，省去踩坑 |
| 2026-10-21 | 界面用 ArkTS/ArkUI 重写，不用 Flutter | 原生体验；FlClash 的 Flutter 界面无法复用 |
| 2026-10-21 | 界面通过 mihomo REST API 控制内核 | 和 Clash Verge 一致，接口现成 |
| 2026-10-21 | 内核只跑在 VpnExtAbility 进程；IPC 只保留 start / stop / status | 其余操作都走 REST API，不需要 FlClash 的 invokeMethod、事件转发、分块传输、跨进程锁 |
| 2026-10-21 | REST API 加 secret，首次随机生成存在 `filesDir/secret` | 手机上其他应用也能访问 127.0.0.1:9090 |
| 2026-10-21 | 运行配置由界面进程生成：订阅 YAML 为底，强制覆盖端口、controller、secret、mode、`tun.enable: false`，并保证 `dns.enable: true` | 内核 `quickSetup` 只读 `home-dir/config.yaml`；Go 侧的 `updateConfig` 覆盖不了 secret 和 dns；TUN 由 startTUN 单独接管 |
| 2026-10-21 | YAML 处理用 ohpm 的 `yaml`（eemeli/yaml 2.8.0），放在普通 `.ts` 文件里 | ohpm 上没有 js-yaml；`.ts` 不受 ArkTS 严格类型限制 |
| 2026-10-21 | 包名 `com.gc.harmonyclash` | 自用 |
| 2026-10-21 | 首页先采用 ArkUI `backgroundEffect` 做通透层级，连接主视觉与状态变更用 springMotion；系统沉浸光感留给后续原生标题栏/底部 Tabs 适配 | API 26 的系统沉浸光感对普通页面区域并非全面生效，避免把普通卡片误称为系统材质；分阶段真机验证动效与功耗 |
| 2026-10-22 | 当前内核模式与下次连接模式分开；运行配置使用成功启动时的名称和版本快照，恢复已有会话时身份保持未知 | 首份配置可在直连运行中导入，不能把待用规则模式冒充当前内核状态，也不能把资料库选中项误标为正在运行 |
| 2026-10-22 | VPN 连接/断开与普通操作分别互斥，异步内核请求按会话代数校验结果 | 测速和订阅下载不得锁住断开按钮，断开后的迟到响应不得恢复旧代理组或覆盖新会话反馈 |
| 2026-10-25 | 以手机实际安装的 FastClient 为信息架构参考，整体重排仪表盘、代理、配置三页，移除蓝色大光环和装饰玻璃 | 首屏优先展示真实状态与常用操作，代理组和节点成为操作主体；仅调整色值、字号和空态不能解决页面结构问题 |
| 2026-10-25 | 用浅色/深色语义颜色资源驱动界面；EntryAbility 同步系统栏，添加配置使用独立 Sheet | 避免页面、状态栏和手势区各自固定颜色；导入任务不再把资料库列表推离视口 |
| 2026-10-25 | 代理页采用固定组标签、搜索及测速工具区，双列节点网格独立滚动 | 长节点列表滚动时仍能切组和筛选，缩短从进入页面到找到目标节点的路径 |
| 2026-10-25 | 通过 `/connections` 只提取累计上传、累计下载和连接数，用单调时间差分计算速度 | 复用内核现成接口；不把连接目标、应用、规则等敏感明细放入 UI 状态，不伪造速率和趋势样本 |
| 2026-10-25 | 统计轮询使用页面可见性与独立监控代数，和 VPN 会话代数共同校验；每次请求完成后约 2 秒再采样 | 避免慢请求并发堆积；后台、断开及重连后的迟到结果不得写回或重新启动计时器，统计不能阻塞停止 VPN |
| 2026-10-25 | 搜索改为顶栏按需模式，过滤所有组的成员并隐藏零匹配组，统一协调浏览组 | FastClient 实物对照表明旧版常驻框、仅当前组筛选和切组清词与参考不一致；不能把单个筛选样本当作模式交互验收 |
| 2026-10-25 | 曾试验普通连接通知，后按用户决定移除 | 可划走通知不满足用户要的常驻状态，连接流程不再申请通知权限 |
| 2026-10-25 | VPN 启动和系统资源销毁共用生命周期队列，入口立即失效旧代数；资源标记只在真正销毁后清除 | stop 不等待通知即可关闭转发，setup/create 的迟到返回不能复活旧会话；销毁失败不能放行下一次 create |
| 2026-10-25 | 连接状态保留在仪表盘；系统 VPN 图标由系统状态栏控制 | API 26 真机上 `isOngoing` 与 `isUnremovable` 同时为 true 仍可左滑删除；应用无法单独显示自身状态栏图标而隐藏通知卡片 |
| 2026-10-25 | 离线代理目录直接解析原始订阅 YAML，与内核运行组和选中状态分离 | 未连接时可浏览已知本地成员；不启动内核，不猜测远程提供者，不将离线目录冒充运行选择或测速结果；连接后切回真实内核数据 |

## 2026-10-25：页面与运行统计

- `pages/Index.ets`：仪表盘显示紧凑连接操作、真实速度/趋势、模式、累计值及运行配置；代理页提供组标签、搜索和双列节点；配置页以订阅列表为主体，整卡选择、菜单操作和独立导入 Sheet 分工明确。底部使用图标和文字导航，不再沿用胶囊模式按钮的外观。
- `resources/base/element/color.json` 与 `resources/dark/element/color.json`：定义同名语义颜色；`EntryAbility` 让应用跟随系统主题，并在主窗口创建、前台恢复和系统配置变化时同步状态栏、导航栏颜色。
- `api/MihomoApi.ets#getTrafficTotals()`：读取 `GET /connections`，验证累计值非负且有限，连接字段仅接受数组或 `null`，只返回 `uploadTotal`、`downloadTotal` 和连接数。内核 `tunnel/statistic/manager.go` 在无活动连接时保留 Go nil 切片，经路由 JSON 序列化为 `null`，应明确转换为真实零连接；缺字段或其他类型仍报格式错误。明细不进入界面状态；统计失败不把可能含连接信息的错误体写入日志或通用提示。
- `api/TrafficStats.ets`：`TrafficSnapshot.ready` 表示累计值与连接数可用，`speedReady` 表示已有两次连续有效采样，`unavailable` 区分请求失败和等待首个样本；失败快照整体发布，成功或停止后清除此标记。速率以字节/秒表示，历史最多 30 个真实差分点；未知数值为 `-1`，展示层格式化成 `—`。首次、错误恢复、计数回退或时间未前进时只建立新基线，不补零或跨未知区间生成曲线。
- 速度按累计字节差除以实际采样秒数计算。时间来自 `systemDateTime.getUptime(STARTUP, false)`，是系统启动后的单调毫秒数，避免系统时间校准影响速度；历史 `sampledAt` 不是 Unix 时间戳。
- 页面确认 VPN 运行且可见后启动监控；`onPageHide` 覆盖应用退后台，`aboutToDisappear` 负责组件销毁清理，均释放定时器与差分基线。`onPageShow` 先查询 VPN 状态再恢复。连接/断开立即失效旧监控代数，不等待统计 HTTP 返回；停止失败且内核仍运行时可重新建立采样。
- 搜索业务从 Builder 中抽出：`matchedProxyNames` 使用原始关键词做忽略大小写的字面包含匹配，不 trim、不解释正则；`visibleProxyGroups` 隐藏零结果组，`reconcileProxyGroup` 保持当前有效组或切至首个匹配组，零结果时记住最后有效组。清空恢复全部组及最后有效组，切组保词；进入时一次性申请输入焦点，清空不重复申请。退出、离开代理页及会话失效会清词，`onBackPress` 不抢占配置 Sheet 的返回。

本轮状态、统计与搜索的 32 项针对性检查通过，包含空连接 `null` 的 API 到轮询回归、失败态恢复、稳定组名下整体替换 `proxySelections` 映射及 7 项真实搜索方法检查；这些是可控依赖模拟。最初 25 项未覆盖搜索，单个“香港”筛选样本不代表交互一致性已验收。搜索修正后的 HAP 已编译签名并覆盖安装，真机确认进入弹键盘、跨组过滤及切组保词、清空保组不重弹键盘、两次 Back 与箭头退出、大小写/空格/字面管道符规则。此前统计、动态图标色、全宽折线、明暗及系统栏、节点切换和 `110 ms` 测速样本结果保留。配置添加 Sheet 的 Back 关闭未被搜索返回处理抢占；该轮已退出搜索，恢复手动组“示例策略组”及选中“示例节点A”，保持用户该轮原有的 VPN 运行状态，`vpn-tun` 为 `172.19.0.1`。未逐个验证 47 节点，未重新验证成功导入/更新全路径，也未测试大文件吞吐或长时间稳定性。

## 2026-10-25：VPN 生命周期与连接状态

- `VpnExtAbility` 的 `lifecycleQueue` 串行执行启动与系统资源销毁，`lifecycleEpoch` 在 start/stop 入口递增，`destroyed` 阻止扩展销毁后的新启动。stop 同步停止内核转发和监听；后续在队列中等待系统 destroy。`coreReady` 覆盖 setup 完成但 create 尚未返回的阶段，`vpnCreated` 在 create 返回后立即置位，只有 destroy 成功才清除。清理失败保留资源标记，后续启动先重试清理。
- 用户确认可划走的普通连接通知没有意义后，移除通知实现、权限申请和 IPC 通知错误。连接状态来自真实 VPN/TUN 状态，在仪表盘显示；通知不能作为隧道存活的前置条件或状态来源。曾经的通知实现和 API 26 不可划走探针保留在变更记录中，仅作历史试验。
- 状态栏的应用图标由通知产生，不能通过当前公开接口单独显示而不保留通知卡片。[华为状态栏说明](https://consumer.huawei.com/cn/support/content/zh-cn16115724/)提供系统 VPN 图标开关；它由系统显示，与 HarmonyClash 应用图标不同。

## 2026-10-25 回装的页面与资源及后续反馈

- 仪表盘正常连接/断开以连接卡为唯一状态展示；没有真实趋势时不绘制空图框，也不显示“等待采样”等解释占位。真实未知数值仍显示 `—`，统计错误提示继续保留。最终离线截图 `/tmp/offline-final-dashboard.jpeg` 已真机确认。
- 内置 imagegen 生成图标接入 AppScope 与 entry 的分层资源，提示词留在 `docs/assets/harmonyclash-icon-prompt.txt`；`/tmp/harmonyclash-final-icon.jpeg` 已确认真机桌面大文件夹中的最终纯底双环图标。
- `profile/ProxyCatalog.ts` 从原始 YAML 提取本地节点名称、类型、策略组及已知成员，不返回服务器或凭据，不合成 GLOBAL，不下载提供者或读取外部缓存；未知展开结果通过 warnings 和 unloadedProviders 明示。`Index.localProxyCatalog` 区分本地目录与运行数据，加载本地时清空运行选择及延迟；没有 YAML 组但有本地节点时仅聚合为“全部节点”浏览组。配置来源变化重建目录并退出旧搜索；连接后从真实 REST 恢复运行组、当前选择和测速，断开回到只读本地目录，旧在线请求不能覆盖本地结果。
- 真机 `/tmp/offline-nodes.jpeg` 显示本地 47 成员、2 个真实组，无 GLOBAL、使用中或测速入口，`vpn-tun` 不存在；CDN 搜索 3 卡及“香港”6 卡切组保词分别见 `/tmp/offline-cdn.jpeg`、`/tmp/offline-hongkong-switch.jpeg`，均未建立 TUN。重新连接后 `/tmp/final-online-nodes.jpeg` 恢复 3 个真实运行组（含 GLOBAL）、当前“示例节点A”和测速入口。当前 44 项状态检查包含 10 项离线增量和 2 项测速反馈增量，解析使用真实 yaml 包，SDK/网络仍模拟；另有 15 项目录解析及 strict TypeScript 检查通过。提供者警告和坏 YAML 等边界不冒充真机通过。
- 用户补充要求单节点/整组测速成功只刷新卡片延迟，不再设置“测速完成”反馈；进行中仅按钮显示状态，去掉重复进度块，失败继续显示就地错误。2 项真实状态方法检查已覆盖这三个阶段。最终版已构建并覆盖安装（`/tmp/harmonyclash-speed-clean-build.log`），`/tmp/speed-clean-single.json` 确认单节点 108 ms 无完成/进度块；`/tmp/speed-clean-group-busy.jpeg` 仅按钮显示“测速中…”，`/tmp/speed-clean-group.json` 及同名截图确认当前香港 6 卡仅更新为 110/117/100/98/229/750 ms，无完成提示。此样本不代表全部 47 个节点的测速或连通性已验证。修改前 `/tmp/final-online-speed.json` 的 101 ms 与完成反馈仅作为旧版重复提示证据。
- 最终收尾已退出搜索、清词并返回仪表盘，保留当时的“示例节点B”选择及开启的 VPN；`/tmp/final-speed-clean-dashboard.jpeg` 显示真实速度、累计和已连接状态，无冗余 notice，`vpn-tun` 为 `172.19.0.1`、`UP RUNNING`。原订阅保留，未更新或删除。

## 内核接口要点（来自 `ref/FlClash-ohos/core`）

- `quickSetup(cb, initParams, setupParams)`：initParams `{"home-dir", "version"(API 版本)}`；setupParams `{"selected-map", "test-url"}`；读取 `home-dir/config.yaml` 并应用，cb 返回空串表示成功。
- `startTUN(protect, resolveProcess, fd, stack, address, dns)`：address 如 `172.19.0.1/30`；dns 为 `0.0.0.0` 表示劫持全部 DNS。
- `stopTun()`：关 TUN，同时停掉 mixed-port 等监听（external-controller 不受影响）。
- `updateDns("ip:53,…")`：Go 在鸿蒙上读不到系统 DNS，要由 ArkTS 侧监听网络变化后推送。
- `suspend(bool)`：设备休眠时暂停。
