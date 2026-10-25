# 开发指南：环境、构建、调试

## 本机环境

- DevEco Studio 26.0.0，SDK 在 `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony`（API 26，含 native/llvm）。
- 命令行工具都在 DevEco 包里（不需要开着 DevEco）：hdc 在 `sdk/default/openharmony/toolchains/hdc`，node/ohpm/hvigor 在 `Contents/tools/` 下。
- Go：brew 装了官方 go 1.27.3（只当 bootstrap 用）；ohos 版 Go 1.24.5 在 `~/sdk/ohos-go`（只在编内核时当 GOROOT，没改全局 PATH）。
- 签名：公开的 `build-profile.json5` 不含个人证书、密码和签名配置。需要真机安装时，在 DevEco Studio 中配置自己的 HarmonyOS 签名；原作者本地配置备份为被 `.gitignore` 排除的 `build-profile.local.json5`，不要提交。

## 参考项目

`ref/FlClash-ohos`（gitignore，不入库）：https://github.com/tljk/FlClash-ohos ，`v0.8.96-ohos` 分支，commit a2e8f13，GPL-3.0。只参考内核层。

| 文件 | 内容 |
|---|---|
| `ohos/entry/src/main/ets/extensionAbility/VpnExtAbility.ets` | 创建 VPN 拿 fd 交给 `startTUN`；`protect`；分应用代理；API 23+ 用 `getConnectOwnerUidSync` 按进程匹配 |
| `ohos/core/src/main/cpp/napi_init.cpp` + `types/libcore/Index.d.ts` | N-API 封装 |
| `ohos/entry/src/main/ets/entryability/EntryAbility.ets`、`TempAbility.ets`、`utils/Rpc.ets` | 界面进程 ↔ 扩展进程 IPC |
| `ohos/entry/src/main/ets/managers/NetworkManager.ets`、`PowerManager.ets` | 推送系统 DNS、休眠暂停 |
| `core/`（Go）、`.github/workflows/build.yaml` | 内核源码和交叉编译方式 |

## 内核编译

`GOOS=openharmony` 官方 Go 不支持，要用 OpenHarmony SIG 的 fork：

```sh
git clone -b release-branch.go1.24 --depth 1 https://gitcode.com/openharmony-sig/ohos_golang_go.git ~/sdk/ohos-go
cd ~/sdk/ohos-go/src && GOROOT_BOOTSTRAP=$(go env GOROOT) ./make.bash
```

内核源码 submodule `core/Clash.Meta` 指向 `git@github.com:tljk/Clash.Meta.git` 的 `v0.8.94`（commit b77fb42），已用 https 拉好：
`git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --depth 1 core/Clash.Meta`

从仓库根目录执行以下命令，再在 `ref/FlClash-ohos/core` 下编译（参数来自参考项目 `build_config.yaml`）：

```sh
SDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony
PROJECT_ROOT="$(pwd)"
cd ref/FlClash-ohos/core
env PATH=$HOME/sdk/ohos-go/bin:$PATH GOROOT=$HOME/sdk/ohos-go GOTOOLCHAIN=local \
  GOOS=openharmony GOARCH=arm64 CGO_ENABLED=1 \
  CC=$SDK/native/llvm/bin/aarch64-unknown-linux-ohos-clang CFLAGS="-O3 -Werror" \
  go build -ldflags="-w -s" -tags=with_gvisor -buildmode=c-shared \
  -o $PROJECT_ROOT/build/arm64-v8a/libclash.so .
```

产物约 48 MB，只依赖 `libc.so`。编完要拷进工程（这两个目录被 gitignore）：
- `build/arm64-v8a/libclash.so` → `core/libs/arm64-v8a/`
- `build/arm64-v8a/libclash.h` 和 `ref/FlClash-ohos/core/bride.h` → `core/src/main/cpp/includes/arm64-v8a/`

## 应用构建、安装、调试

```sh
C=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$C/sdk PATH=$C/tools/node/bin:$C/tools/ohpm/bin:$PATH
HDC=$C/sdk/default/openharmony/toolchains/hdc
ohpm install --all
node $C/tools/hvigor/bin/hvigorw.js --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
$HDC install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC shell aa start -a EntryAbility -b com.gc.harmonyclash
$HDC shell uitest dumpLayout -p /data/local/tmp/layout.json   # 拉回来找控件 bounds，再 uitest uiInput click x y
$HDC shell hilog -x | grep harmonyClash                        # 看日志
$HDC fport tcp:19090 tcp:9090                                  # Mac 上 curl 内核 REST API
```

## 2026-10-25：整体重做验证入口

本轮先查看手机实际安装的 FastClient，再重排三页信息结构。参考首页截图暂存于本机 `/tmp/harmonyclash-before-redesign.jpeg`；该图是 FastClient，不是本工程新版首页，不能混用作验收截图。

安装、启动、截屏及其他设备操作应通过 `hdc list targets -v` 找到本机设备，并显式指定目标；构建沿用上节命令。原测试机上的最终 HAP 已构建、签名并覆盖安装，既有订阅保留；统计空闲响应、明确错误态、图标动态色和图表缩放的修复均已回装复核。

```sh
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC list targets -v
HDC_TARGET="替换为上一步显示的设备ID"
$HDC -t $HDC_TARGET install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC -t $HDC_TARGET shell aa start -a EntryAbility -b com.gc.harmonyclash
$HDC -t $HDC_TARGET shell snapshot_display -f /data/local/tmp/harmonyclash-dashboard.jpeg
$HDC -t $HDC_TARGET file recv /data/local/tmp/harmonyclash-dashboard.jpeg /tmp/harmonyclash-dashboard.jpeg
```

本机的针对性检查入口为 `/tmp/harmonyclash-state-check.cjs`，运行 `node /tmp/harmonyclash-state-check.cjs`，同目录需保留增量模块 `/tmp/harmonyclash-search-cases.cjs` 与 `/tmp/harmonyclash-offline-cases.cjs`。最终去测速提示版本通过 44 项（原 32 项加离线 10 项、测速反馈 2 项）：直接读取并转译真实 Index、统计模块和 ProxyCatalog，使用真实 yaml 解析包，注入可控 IPC、HTTP、时钟和定时器，不复制业务实现，也不连接真实 VPN。包含既有连接/配置状态、节点选择映射、统计差分/空连接/错误恢复/后台清理及 7 项真实搜索方法检查；离线增量覆盖无配置空态、真实本地组/类型、离线搜索切组、选择测速零 REST、连接在线/断开本地、旧在线响应隔离、换配置退出搜索、无组聚合、坏 YAML 明确错误、提供者警告按组及重载清理。最新 2 项分别核对单节点和整组：开始无冗余进度，成功只更新延迟、不设置 feedback/notice，失败保留就地错误。TextInputController/FocusController 只做最低 mock，一次焦点标志检查不能证明系统键盘真实弹起。最初 25 项没有搜索断言，单个“香港”6 节点样本不能视为搜索交互一致性验收。

搜索修正前一轮的真机样本结果：`/tmp/harmonyclash-redesign-live-final.jpeg` 显示真实空闲 `0 B/s`、累计 `29 KB/23 KB`、连接数 `2` 和真实折线。实际点击“示例节点A”后摘要、使用中卡片及反馈同步更新，界面转储保存在 `/tmp/harmonyclash-selected-final.json`；单节点测速实际返回 `199 ms`，搜索“香港”显示 `6` 个节点。最终版本的 `/tmp/harmonyclash-final-traffic.jpeg` 确认动态图标颜色正常、独立 `Shape` 共享 viewport 后折线铺满全宽；`/tmp/harmonyclash-final-proxy-test.jpeg` 确认测速 `110 ms`、短反馈和选中态同步。URL/YAML 导入 Sheet 与错误提示已操作核对；配置日期为 `YYYY/MM/DD`，原生菜单可显示“更新订阅”，未执行更新或删除。系统 dark/light 切换时页面与系统栏同步，随后已恢复用户原 light。以上未覆盖逐个测试全部 47 节点、成功导入新订阅及更新全路径、大文件吞吐或长时间稳定性。该轮测试收尾已选回“示例节点A”并关闭本应用 VPN，`ifconfig vpn-tun` 返回 `No such device`；已清除断开提示并返回离线仪表盘，最终首屏保存在 `/tmp/harmonyclash-ready-final.jpeg`。

### 同日后续：搜索模式实物对照与逐项回归

旧版本应用在手动组输入“示例”显示 0 节点（`/tmp/harmonyclash-search-repro.jpeg`），FastClient 同词只留下 GLOBAL 与“示例策略组”卡（`/tmp/fastclient-search-groupfilter.jpeg`）。这证明此前只测“香港”样本遗漏了跨组筛选及模式交互。新版已编译签名、USB 覆盖安装，原订阅保留，真机逐项结果如下：

- 默认不常驻输入框，顶栏按钮进入后自动取焦点、弹系统键盘：`/tmp/harmonyclash-search-keyboard-ready.jpeg`。
- “香港”显示 6 卡，切自动组仍保留关键词和 6 卡：`/tmp/harmonyclash-search-switch-fixed.json`。“示例”只保留 GLOBAL 和“示例策略组”1 卡，并自动切到该组：`/tmp/harmonyclash-search-group-fixed.jpeg`。
- X 清空保持搜索模式和 GLOBAL、恢复全部组，键盘不重弹：`/tmp/harmonyclash-search-clear-fixed.jpeg`。CDN 忽略大小写命中 3 卡：`/tmp/harmonyclash-search-cdn-fixed.jpeg`。
- “ 香港 ”不 trim，“香港|日本”按完整字面量匹配；dump 确认输入原值，两者均为全页空态、0 组标签、无测速入口：`/tmp/harmonyclash-search-{spaces,literal}-fixed.json` 及同名截图。
- 第一次 Back 仅收键盘且仍保留“香港”，第二次退出搜索并清词；左箭头同样退出清词、保持 GLOBAL：`/tmp/harmonyclash-search-{first-back,second-back,arrow-exit}.json`。默认顶栏恢复见 `/tmp/harmonyclash-search-final.jpeg`。

配置添加 Sheet 打开时有 2 个输入框，Back 后为 0 且 Sheet 关闭，未被搜索返回处理抢占，见 `/tmp/harmonyclash-sheet-back-{open,closed}.json`。本轮开始时用户已自行启动本应用 VPN；覆盖安装使其停止后已恢复连接。收尾已退出搜索并清词、恢复手动组“示例策略组”和选中“示例节点A”，见 `/tmp/harmonyclash-search-ready.jpeg`；再次确认 `vpn-tun` 为 `172.19.0.1`，保持用户进入本轮前的运行状态。原订阅保留，未执行更新或删除。FastClient 仅做导航和搜索对照，已退出搜索并恢复原手动组，未操作其订阅或 VPN。未测范围仍包括逐个验证 47 节点、成功导入/更新全路径、大文件吞吐和长时间稳定性。

真机核对时分别检查仪表盘、组标签/搜索/双列节点、配置列表与导入 Sheet，并复核系统明暗切换及状态栏/手势区颜色。运行统计需建立本工程 VPN 后观察真实累计变化，至少等待两次有效采样后才有速度；退后台后日志应记录统计暂停，回前台先确认状态再重新采样。现有其他 VPN 的处理仍遵循下节要求，不清数据、不卸载其他应用。

### 同日后续：普通通知试验已撤回

旧版本曾通过 `vpn/VpnNotification.ets` 发布“VPN 已连接”，并在断开时撤销。真机证据 `/tmp/vpn-notification-{connected,retained,stopped,reconnected}.jpeg` 只证明普通通知路径；API 26 将 `isOngoing`、`isUnremovable` 都设为 true 后仍可左滑删除，见 `/tmp/vpn-probe-flags.jpeg`、`/tmp/vpn-probe-swipe.jpeg`。真正禁止移除的 [系统接口](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-notification-kit/js-apis-inner-notification-notificationRequest-sys.md)需要普通应用无法取得的权限。用户决定移除普通通知后，源码已删除通知模块、前台授权请求和独立通知错误字段，不再把这套历史试验当作当前连接功能。

只需要连接状态图标时，系统可显示 VPN 图标：[华为状态栏设置说明](https://consumer.huawei.com/cn/support/content/zh-cn16115724/)路径为“设置 > 通知和状态栏 > 状态栏 > VPN”。应用自己的状态栏图标来自通知；不能单独保留应用图标，同时隐藏通知中心卡片。不要擅自修改用户手机的系统开关。

VPN 生命周期的 `lifecycleQueue`、入口代数与底层销毁屏障继续保留。去通知版构建并覆盖安装后，真机连接创建 `vpn-tun`（`172.19.0.1`、`UP RUNNING`），下拉通知栏无 HarmonyClash 卡片；断开后 `vpn-tun` 消失，恢复该轮进入时的断开状态。证据见 `/tmp/harmonyclash-remove-notification-build.log`、`/tmp/no-notification-connected.json` 和 `/tmp/no-notification-shade.jpeg`。配置及节点目录沿用先前验收结果，本轮未重复全路径测试。旧 `/tmp/harmonyclash-notification-check.cjs` 的 18 项只适用于含通知模块的历史源码，不能当作当前版回归结果。

### 同日后续：仪表盘、图标与离线目录回装结果

正常连接/断开不再设置重复 notice，连接卡直接反映状态；普通连接通知已移除。速度区没有足够真实趋势时不显示解释文字和空图框，未知数值继续使用 `—`。离线目录版本的真机仪表盘见 `/tmp/offline-final-dashboard.jpeg`，已确认没有例行 notice 和网速解释占位。

内置 imagegen 生成的前景/背景已接入 AppScope 与 entry 的分层图标，提示词在 `docs/assets/harmonyclash-icon-prompt.txt`。`/tmp/harmonyclash-final-icon.jpeg` 已确认真机桌面大文件夹内的最终纯底双环图标；此结论来自实际桌面显示，不是仅看资源文件或编译结果。

离线目录由 `profile/ProxyCatalog.ts` 解析原始 YAML，只提供名称、类型、组成员及未加载提供者的提示；不下载远程内容、不启动内核/TUN、不提供真实运行选择或测速结果。已在当前订阅真机核对：`/tmp/offline-nodes.jpeg` 显示本地 47 成员、2 个真实 YAML 组，无 GLOBAL、使用中和测速入口，`ifconfig vpn-tun` 返回 `No such device`；`/tmp/offline-cdn.jpeg` 中 CDN 忽略大小写匹配 3 卡，`/tmp/offline-hongkong-switch.jpeg` 中“香港”6 卡、切到自动组仍保词，全程未建立 TUN。中文通过 IME 输入 `xianggang` 后选择“香港”候选；首次 HDC Unicode 未正确输入，不能将其当搜索失败或通过样本。连接后真实运行组、当前选择和测速入口恢复，见 `/tmp/final-online-nodes.jpeg`。提供者未加载、解析失败等边界仅有本机状态/解析检查，未全部真机操作。

### 同日用户补充：去掉测速完成提示（已回装回归）

用户明确要求测速成功不再显示“测速完成”等反馈，也不要与按钮状态重复的进度块。最终行为为：测速中仅在对应按钮展示处理中，成功只更新卡片延迟；真正失败继续显示错误。单节点和整组均适用。修改前在线“示例节点A”单节点返回 101 ms，`/tmp/final-online-speed.json` 同时含使用中、101 ms 和完成反馈；此文件只证明旧版仍有重复提示，不作为删除提示后的最终验收。

最终去提示版构建日志为 `/tmp/harmonyclash-speed-clean-build.log`，已覆盖安装并保留原订阅。真机 `/tmp/speed-clean-single.json` 确认单节点 108 ms 且无完成/进度块；`/tmp/speed-clean-group-busy.jpeg` 显示仅按钮“测速中…”、没有额外进度块；`/tmp/speed-clean-group.json` 与同名截图显示当前香港 6 卡为 110/117/100/98/229/750 ms，无完成提示。整组仅核对当前可见 6 卡，不等于全部 47 节点的测速或连通性通过；失败保留错误由 2 项新增状态检查覆盖，未为本次真机样本主动制造失败。

去测速提示版验收时退出搜索并清词、回到仪表盘，保留当时“示例节点B”的选择和开启的 VPN，没有为恢复此前节点而覆盖选择。`/tmp/final-speed-clean-dashboard.jpeg` 显示当时已连接、真实速度和累计且无冗余 notice，`vpn-tun` 为 `172.19.0.1`、`UP RUNNING`。后来用户撤回连接通知需求；当前版本的设备状态以最新回装记录为准。

## 踩过的坑

- **无线调试安装**：在手机无线调试页查看当前 IP 和端口，使用 `hdc tconn IP:端口`，确认 `hdc list targets -v` 为 Connected 后，所有后续命令显式指定 `hdc -t IP:端口`。2026-10-22 已无线覆盖安装并启动成功，无须 USB。真机 `snapshot_display -f` 的文件名必须以 `.jpeg` 结尾，`.png` 会被拒绝。
- **2026-10-25 统计时钟与后台生命周期**：SDK 的 `systemDateTime.getUptime(STARTUP, false)` 返回包括深睡时间的启动后单调毫秒数；速度必须使用两次采样的实际差值，不能直接除以写死的两秒。`onPageHide`/`onPageShow` 的本地 SDK 声明明确覆盖应用退后台/回前台；只依赖 `aboutToDisappear` 会漏掉组件仍存在的后台场景。统计轮询每次请求完成后再安排下一次，断开不等待 HTTP，页面隐藏后旧请求也不能重新安排计时器。
- **2026-10-25 空闲统计响应**：真机日志显示监控启动后曾恢复有效采样，随后再次不可用；本地内核 `tunnel/statistic/manager.go` 的空连接切片未初始化，`hub/route/connections.go` 直接序列化快照，因此无活动连接时 `connections: null` 是合法响应。解析必须明确接受此值为零连接，保留累计数据并允许后续真实零速率；缺失连接字段或错误类型仍拒绝。日志排查使用 `hdc -t $HDC_TARGET shell hilog -x -T harmonyClash.ui`，`-T` 才是标签过滤，不打印 secret 或连接明细。修复版已回装并观察到有效累计及真实空闲零速率，`null` 本身的明确解析由针对性回归覆盖。
- **ArkUI Path 真机坐标与模糊图层**：`Path.commands` 数值使用 px，单独把容器设为 56vp 不会同步缩放路径。通过 `Shape` 包裹 Path，外层设 56vp，`viewPort` 显式使用 `56px`，线宽也使用 px，才能在高密度设备保持预期尺寸。独立 `Circle().blur()` 在目标真机出现矩形边界，已去除这些图层并用渐变/按钮阴影代替；不能只凭编译判断视觉正确。
- **hdc 服务**：DevEco 开着时用的是它启动的 hdc server；退出 DevEco 后要自己 `hdc start`。在 Claude Code 里启动 hdc server 必须**关掉命令沙箱**（`dangerouslyDisableSandbox`），否则 server 访问不了 USB，`list targets` 一直为空。
- **本次 hdc 恢复**：`ioreg -p IOUSB -w0` 能看到 HDC Device 后，执行 `hdc kill`、`hdc start`，`hdc list targets` 重新出现 `$HDC_TARGET`。
- **VPN 已存在（2203002）**：`VpnConnection.create()` 返回 `VPN exist already, please execute destroy first` 时先核对系统 VPN。2026-10-21 真机上 `ifconfig vpn-tun` 显示已有地址 `10.0.0.254`，与本工程的 `172.19.0.1/30` 不同；须在手机上关闭现有 VPN 后再验证本工程 TUN。不要用清除应用数据或卸载其他应用来处理。
- **TUN 真机验证**：关闭已有 VPN 后，本工程的 `vpn-tun` 地址为 `172.19.0.1/30`。经 `hdc fport tcp:19090 tcp:9090`，带应用私有目录中 `secret` 的 Bearer 请求可读取 `/connections`；其他应用显示 `type=Tun` 且流量增长。手机浏览器能打开 IANA 页面。不要把 secret 打印到终端或日志。
- **连接包名权限**：`connection.getConnectOwnerUidSync` 能查到 UID，但 `bundleManager.getBundleNameByUidSync` 查询其他应用时抛出 201（permission denied），即使模块已声明 `GET_BUNDLE_INFO`。当前连接的 `process` 因而为空，不影响 TUN；后续做分应用功能前需处理这一系统权限限制。
- **手机 USB 掉线后 hdc 列不出设备**：`ioreg -p IOUSB` 能看到 HUAWEI "HDC Device"，但 `$TMPDIR/hdc.log` 里是 `libusb ... device not responding` / `OpenDeviceMyNeed childRet:-1`，说明手机端 USB 调试服务卡住了。可先尝试上面的 `hdc kill` / `hdc start`；仍不行再拔线 → 开发者选项里 USB 调试关了再开 → 重插。

- `build-profile.json5` 的 SDK 版本要写 `"26.0.0"`；旧格式 `"5.0.0(12)"` 会报 `api version parameter is illegal`。
- 参考项目的 `core/hvigorfile.ts` 依赖 Flutter 的 setup 插件，不能直接搬，要换成纯 `harTasks`。
- submodule URL 是 SSH 形式，没配 GitHub SSH key 时用上面的 insteadOf 改走 https。
