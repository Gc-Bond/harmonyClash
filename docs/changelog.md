# 进度与变更记录

新的写在最上面。

## 2026-10-25

- **准备公开仓库**：新增 README、GPL-3.0 许可与上游归属说明，修正模块许可元数据；公开的构建配置移除本机签名证书路径和密码，私有副本保留在 gitignore 文件中。仪表盘、代理和配置三张真机截图经订阅/节点信息匿名化后加入 README。原本地历史含签名配置，公开分支改从清理后的工作树建立初始提交，旧历史仅保留在本地私有 Git 引用，不推送到 GitHub。

- **按用户决定移除普通连接通知**：可划走通知无法满足常驻要求，用户明确要求去掉。删除 `VpnNotification.ets`、连接时的通知授权申请、扩展发布/撤销调用和 IPC 通知错误字段；TUN 建立后直接返回真实状态，仪表盘继续显示连接状态。状态栏应用图标依附通知，不能在无通知卡片时独立显示；系统 VPN 图标可由手机“设置 > 通知和状态栏 > 状态栏 > VPN”控制，未改用户系统开关。新包构建成功（`/tmp/harmonyclash-remove-notification-build.log`）并已 USB 覆盖安装；真机连接显示“VPN 已连接”，`vpn-tun` 为 `172.19.0.1`、`UP RUNNING`，下拉通知栏仅有系统 USB 通知、无 HarmonyClash 卡片（`/tmp/no-notification-connected.json`、`/tmp/no-notification-shade.jpeg`）。随后断开，`vpn-tun` 消失，恢复本轮开始时的断开状态。此前通知真机探测及 18 项模拟检查仅作历史证据，不代表当前源码验证。
- **去掉测速完成提示（最终版已回装）**：用户指出完成反馈没有意义后，单节点/整组测速成功改为只更新卡片延迟，进行中仅按钮显示“测速中…”，删除重复进度块和成功反馈，失败保留就地错误。最终版构建日志为 `/tmp/harmonyclash-speed-clean-build.log`，已覆盖安装；真机 `/tmp/speed-clean-single.json` 确认单节点 108 ms，无完成/进度块；`/tmp/speed-clean-group-busy.jpeg` 仅有按钮状态，`/tmp/speed-clean-group.json` 及同名截图确认当前香港 6 卡为 110/117/100/98/229/750 ms，无完成提示。此样本不代表全部 47 节点测速或连通性通过。修改前 `/tmp/final-online-speed.json` 的 101 ms 与完成反馈仅作旧版反证。收尾已退出搜索并清词回仪表盘，保留当时“示例节点B”选择和开启的 VPN，`/tmp/final-speed-clean-dashboard.jpeg` 显示真实速度/累计且无冗余 notice，`vpn-tun` 为 `172.19.0.1`、`UP RUNNING`；原订阅保留，未更新或删除。
- **常驻通知真机反证（用户要求尚未实现）**：在 HarmonyOS 7.0.0.109 / API 26 上同时设置 `isOngoing: true` 与 `isUnremovable: true`，编译、覆盖安装及连接通知均成功；从 `(1130, 749)` 左滑至 `(100, 749)` 后通知立即消失，而 `vpn-tun` 仍为 `172.19.0.1`，见 `/tmp/vpn-probe-flags.jpeg`、`/tmp/vpn-probe-swipe.jpeg`。公开 SDK 与[官方字段文档](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-notification-kit/js-apis-inner-notification-notificationRequest.md)将两字段标为预留；本次以设备结果确认无效，最终源码已移除两个标志。真正禁止删除的 `isRemoveAllowed` 需要 `ohos.permission.SET_UNREMOVABLE_NOTIFICATION` 且属[系统接口](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-notification-kit/js-apis-inner-notification-notificationRequest-sys.md)。[长时任务](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/task-management/continuous-task.md)与 [LiveViewKit](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/liveview-introduction-V14)也允许用户删除关联通知，不能作为普通 VPN 应用的强常驻替代；Huawei 简介为 V14 归档，不替代 API 26 实机结果，不以重发通知冒充不可清除。
- **VPN 生命周期竞态修复（本机检查通过，普通路径真机回归）**：启动与系统 VPN 销毁共用队列，start/stop 入口立即失效旧代数，stop 同步关闭转发及监听；迟到 setup/create 必须先清理，destroy 失败保留资源标记并阻止新建跨过清理屏障，扩展销毁后禁止重启。当前源码的 44 项状态检查通过（原 32 项、离线 10 项、单节点/整组测速反馈 2 项），均真实转译源码、模拟 SDK/IPC/HTTP 等依赖，不是手机运行结果；旧通知版曾通过 18 项生命周期/通知专项，不能作为去通知版结果。另有 15 项真实 YAML 目录解析及 ProxyCatalog strict TypeScript 检查通过。测速新增检查确认开始无重复进度、成功只更新延迟且无 feedback/notice、失败保留错误。普通启停和重连已回装核对，快速竞态等未实操分支仍不标真机通过；通知点击仅属历史试验。
- **仪表盘提示清理、图标与离线目录已回装核对**：正常成功/断开不再显示与连接卡重复的 notice；无真实趋势时移除网速解释占位和空图框，保留未知数值 `—` 及真实错误，真机离线仪表盘见 `/tmp/offline-final-dashboard.jpeg`。内置 imagegen 图标已接入 AppScope/entry 分层资源，提示词留存于 `docs/assets/harmonyclash-icon-prompt.txt`，`/tmp/harmonyclash-final-icon.jpeg` 确认真机桌面大文件夹显示纯底双环图标，通知使用新图标。离线目录从本地 YAML 提取已知名称/类型/真实组，不下载提供者、不启动内核：`/tmp/offline-nodes.jpeg` 显示 47 成员、2 真实组，无 GLOBAL、使用中和测速入口，TUN 不存在；`/tmp/offline-cdn.jpeg` 命中 CDN 3 卡，`/tmp/offline-hongkong-switch.jpeg` 命中香港 6 卡并切组保词，全程无 TUN。中文须通过 IME 输入 `xianggang` 再选“香港”，首次 HDC Unicode 未正确输入不计结果。重连后 `/tmp/final-online-nodes.jpeg` 恢复含 GLOBAL 的 3 个真实运行组和测速入口；提供者/坏 YAML 等边界仅本机检查通过，未全部真机操作。
- **VPN 连接通知（普通通知基本路径通过）**：用户点击连接时从前台申请通知授权，拒绝不阻止 VPN；VpnExtAbility 在真实 TUN 成功后以固定 id `1001` 发布服务信息通知，点击打开 EntryAbility，`tapDismissed: false`。发布/撤销串行排队并通过代数失效旧操作，停止、新会话及扩展销毁时清理；通知失败通过独立 `notificationError` 返回，不把已连接 VPN 误报为失败。初版 HAP 已编译回装，真机确认首次授权允许后单条通知、点击回应用且保留、断开后 TUN 消失及通知撤销、重连不重复授权；退桌面后仍单条通知，TUN 为 `172.19.0.1`。生命周期修复和离线目录回装版本再次确认新图标单条通知（`/tmp/final-connected-notification.jpeg`）、点击回仪表盘（`/tmp/final-notification-return.json`）、断开 TUN 消失及通知撤销（`/tmp/final-stopped-notification.jpeg`），随后重连正常。此结果只证明普通通知基本路径，拒绝授权等未测分支不标通过，也不沿用本机状态及搜索验收替代。
- **搜索交互实物对照修正**：用户追问与 FastClient 不一致后，在两应用实际输入“示例”，确认旧版本仅筛当前组导致 0 节点，参考应用则隐藏无匹配组并自动转到 GLOBAL，展示“示例策略组”卡。此前 25 项检查没有搜索断言，“香港”6 节点样本不代表搜索一致性已验收。新版改为顶栏图标进入、自动弹系统键盘，跨全部组过滤成员、隐藏零匹配组，保留仍有效的组或自动选择有结果组；切组保词，X 清空恢复全部组并保留当前组及模式、不强制弹键盘。匹配忽略大小写但保留原始空格，管道符按字面量处理。新增 7 项真实状态方法检查，合计 32 项通过；最新 HAP 已编译签名并 USB 覆盖安装、保留订阅。真机已逐项核对香港 6 卡/切组保词、示例词转 GLOBAL 1 卡、CDN 3 卡、空格和管道词零结果、X 清空、首次 Back 收键盘/第二次退出、箭头退出清词保组。配置添加 Sheet 的 Back 关闭也已真机验证，未被搜索返回吞掉。收尾已退出搜索并清词、恢复手动组“示例策略组”及选中“示例节点A”，确认 `vpn-tun` 为 `172.19.0.1`，保持用户本轮进入前已启用的本应用 VPN 状态；原订阅保留，未更新或删除，未操作 FastClient 的 VPN。此前未测的全部节点、导入更新全路径、吞吐及长时间稳定性仍未补测。
- **以手机实物为参考整体重做三页**：用户反馈此前效果不如手机已安装的 FastClient，本轮先查看实际应用首页和本工程真机截图，再调整信息结构。移除蓝色大光环、渐变玻璃、大胶囊导航和重复连接状态；仪表盘改为紧凑连接操作、真实网速及趋势、出站模式、累计统计和运行配置。代理页改为固定组标签、搜索和测速工具区，双列节点网格独立滚动，保留手动/自动组边界与节点就地反馈。配置页保留订阅列表为主体，整卡选择、额度/到期/更新时间、次要操作菜单，添加配置进入独立 Sheet。
- **浅深色及系统栏统一**：页面使用 base/dark 同名语义颜色资源，跟随系统明暗；`EntryAbility` 在主窗口创建、回到前台和系统配置变化时同步状态栏、导航栏，替换固定深蓝系统栏。底部使用图标与文字导航，页面背景延伸到手势安全区。
- **真实运行统计与生命周期**：`MihomoApi.getTrafficTotals()` 从 `/connections` 只提取累计上传、累计下载和连接数，不向界面暴露连接目标等明细。新增 `TrafficStats.ets`，使用系统启动后的单调时间和真实累计差分计算速度，保留最多 30 个真实趋势点；首次采样、错误恢复、计数回退与时间未前进时不伪造速率。页面可见且 VPN 运行时串行采样，每次请求完成后约两秒再读；退后台、页面销毁和断开均释放定时器、失效监控代数，迟到统计不能写回或重新排程，统计不占连接锁且不延迟停止 VPN。保留此前当前/下次模式、运行配置快照及测速下载中允许断开的修复。
- **空闲统计响应与错误态修复**：真机 TUN 连接后的日志显示统计监控已启动且曾成功采样，随后空闲时持续不可用；核对本地内核源码发现无活动连接时 Go nil 切片合法序列化为 `connections: null`，原数组校验误拒绝。现在仅将明确的 `null` 解析为真实零连接，缺字段及错误类型仍拒绝；补充 API 到轮询的空闲回归，累计与连续采样的真实零速率保持有效。统计快照新增 `unavailable`，请求失败明确区别于等待采样，恢复及停止后清除。修复版已回装，真机截图显示真实空闲 `0 B/s`、累计 `29 KB/23 KB`、连接数 `2` 和真实折线。
- **真机交互样本与当前验证范围**：最终 HAP 已编译、签名，并通过 USB 设备 `$HDC_TARGET` 覆盖安装，保留既有订阅，TUN 连接成功。实际点选“示例节点A”后摘要、使用中卡片和反馈同步更新；单节点测速先后返回 `199 ms`、`110 ms`，最终代理页短反馈及选中态同步；搜索“香港”显示 `6` 个节点，URL/YAML Sheet 及错误提示正常。单对象 `$$` Builder 参数让图标动态颜色正常更新，图表采用独立 `Shape` 共享 viewport 后折线铺满全宽，均已回装真机确认。系统 dark/light 切换时页面和系统栏同步，随后恢复用户原 light。直接转译当前源码的状态/时序检查由 11 项扩展为 25 项，全部通过；`git diff --check` 与 `git diff --cached --check` 通过。未逐个验证全部 47 节点、成功导入及更新全路径、大文件吞吐或长时间稳定性。收尾已选回“示例节点A”并关闭本应用 VPN，`ifconfig vpn-tun` 返回 `No such device`，已清除断开提示并返回离线仪表盘。

## 2026-10-22

- **无线调试安装与首页真机复核**：通过用户提供的手机无线调试地址连接成功，最新签名 HAP 覆盖安装并启动，截图确认既有订阅仍在。首张真机截图发现新增 Path 电源图标因 px/vp 坐标差异缩小、偏移，独立 `blur` 圆层也出现矩形边界；改用 Shape 显式像素视口缩放图标，并移除这些模糊圆层，以渐变与按钮阴影维持层次。重新编译、覆盖安装、启动和截屏均成功，首页复截图确认图标大小/居中正常、模糊方块消失，路由模式及所选配置可在首屏看到。本轮未启动 VPN，代理连通性及另外两页交互仍待验收。
- **日常操作与状态可信度返工（本轮待真机验收）**：缩短首页连接主视觉，去掉无助于操作的编号/英文装饰，为路由模式与配置留出更多空间；已有配置时优先展示列表，添加表单按需展开，空资料库直接显示导入入口。节点测速/切换的处理结果和错误现在位于对应节点行下方，收起后回到组顶。修复运行中首次导入订阅、重连后仍沿用直连模式的问题，分别维护当前内核模式和下次连接模式；运行配置名称与版本取自成功启动时的快照，与下次选用配置分开，界面进程重开时不猜测已有会话身份。连接/断开使用独立互斥，测速和订阅下载期间仍可停止；旧会话的迟到响应不能恢复代理组或覆盖新会话。ArkTS/签名 HAP 编译通过；直接转译当前源码并注入可控 IPC/HTTP 的 11 项状态/时序检查通过，覆盖首次导入重连、测速/下载中停止、迟到响应、配置版本和已有会话身份。`git diff --check` 通过。本轮 `hdc` 无可用设备，桌面工具因 DevEco 应用签名校验失败无法进入预览器；**未回装最新 HAP，也未完成最新页面视觉、动效与真实 VPN 联网验收**。
- **策略组来源与节点切换交互修正（待真机回归）**：连接中的手机内核运行配置与 `/group` 返回值核对：当前「示例」配置提供 `示例策略组`（手动 Selector）和 `♻️ 自动选择`（URLTest），第三组 `GLOBAL` 由 mihomo 内核自带。旧代理页把自动组成员与可操作节点混排，且切换反馈只出现在长页顶部，容易被看成“点了没反应”。代理页现在将手动、自动和内核组标明来源与生效条件，手动组优先展示；节点切换与测速均在组内即时显示处理中、结果和错误，并在 PUT 后重新读取 `/group` 校验选中节点。ArkTS/HAP 编译与 `git diff --check` 通过。修改后手机 USB 设备变为 Offline，随后无法发现，原生界面控制服务亦不可用；**尚未回装最新版 HAP，也不能声称真机点按、路由出口和动效已验收**。
- **第 3 步真机三页视觉与手势安全区复核**：USB 连接的 PLR-AL00（HarmonyOS 7.0.0.109）已被 hdc 识别，最新签名 HAP 覆盖安装并启动成功。启动前网卡列表未见活动的 `vpn-tun`。真机分别截图核对概览页、代理断连页和配置页首屏；代理页使用临时启动页构建取图，之后恢复概览为默认启动页并重新编译、回装。发现原深色页面底部手势区为白底，已只让背景通过 `expandSafeArea` 延伸至底部系统安全区，真机复截图确认白色断层消失，页签仍位于安全区内。当前电脑原生界面控制服务持续报 `Sky Computer Use native pipe startup failed`，因此**本轮未在真机完成点按、滚动、动效手感及 VPN/TUN 联通性测试**；不能把三页截图或此前 Previewer 点击算作这些项目已验收。用户手机上的既有配置未清除，也未启动 VPN。
- **第 3 步独立模拟器三页视觉复核**：为绕过独立模拟器窗口无法由当前界面工具直接绑定的问题，临时分别将代理页和配置页设为启动页，逐次编译、安装并截取 Pura 90 Pro 模拟器画面；发现代理断连页短内容被垂直居中、顶部留白过大，给滚动内容设置最小视口高度并显式顶部排布后，模拟器复截图确认修正，配置页布局未受影响。随后已恢复概览为默认启动页，重新编译、安装并截屏确认最终版本。三页真实渲染已逐页看过；底部页签、表单切换、资料库跳转与返回按钮的点击验证来自 DevEco Previewer，独立模拟器里的点击手感和 VPN/TUN 联通性仍未验收。
- **第 3 步无配置模式与跨页反馈修正**：无活动配置时默认选中直连；点规则或全局会提示先导入配置，选中态不再假切换。首次导入后默认规则模式，后续更新不覆盖用户的选择；切换一级页面时清除旧操作提示，避免遮挡新页首屏。DevEco Previewer 已点击确认无配置模式提示、代理断连空态、配置 URL/YAML 两种表单、资料库跳转与返回顶部；ArkTS/HAP 编译通过。DevEco 已将最新 HAP 安装并启动到 Pura 90 Pro 独立模拟器，模拟器截屏确认首页显示新的直连选中态及说明；另外两页不能把 Previewer 的逐页点击算作模拟器验收。
- **第 3 步配置页长页可达性修正**：配置页增加「查看已保存」和「返回顶部」入口；三页共用的滚动容器在切换一级页面时复位。DevEco Previewer 中已点击验证资料库底部空态可完整显示、可返回导入表单，且从底部切换到代理页后从页面顶部显示；URL/YAML 表单切换、代理断连态返回概览、断连时路由模式反馈也已逐项点击核对。最新 ArkTS/HAP 编译成功。Previewer 的拖动手势未能触发滚动，但页内滚动控制器及底部内容已通过实际点击验证；独立模拟器窗口可运行应用，尚未在该窗口完成三页逐项点验。
- **第 3 步三页视觉统一与模拟器验收**：代理页、配置页改为显式深色玻璃材质，补齐断连空态、订阅 URL/YAML 双表单、策略组与节点层级；页面与导入方式使用弹性过渡。Previewer 已逐页检查概览、代理断连态、配置 URL/YAML 表单，文字对比与卡片底色正常；长页滚动在当前预览自动化中未能确认。HarmonyOS 7.0.0 Beta2 Pura 90 Pro 本地镜像已安装；最终 HAP 重新编译成功，已覆盖安装并重启应用，模拟器截屏确认首页真实运行布局与新版导航。独立的 Pura 90 Pro 模拟器窗口已正常显示并运行应用；DevEco 的 Screen Mirroring 工具窗单独显示「No Devices」，不能据此判断模拟器未启动。模拟器内另外两页的交互/截图尚未核实；VPN/TUN 联通性与动画手感仍须实体机复验。
- **第 3 步改用 DevEco Previewer 做日常视觉验收**：手机未连接时，已在 DevEco Studio 预览器成功渲染首页。预览发现连接按钮实际显示为圆角矩形、底部导航被系统预设模糊提亮且未选中文字对比不足；已明确使用圆形按钮与深色玻璃材质，复看两处正常。为兼容 Preview Checker，补齐界面中三个可选实例字段的显式初值。HAP 编译通过。后续页面布局、材质和动效先用预览器逐轮检查；VPN/TUN 联通性以及最终设备上的材质、动画手感仍需真机验收。当时本机虚拟设备镜像尚未就绪，不影响 Previewer 使用。

## 2026-10-21

- **第 3 步视觉重做，先完成首页第一轮**：用户反馈原三卡片界面与动效过于平淡，希望参考鸿蒙 QQ 音乐的动效节奏，逐块打磨。首页改为单一连接主视觉、分层光环与通透材质，触按有回弹，VPN 状态和模式在操作确认后再过渡；原有代理/配置功能未改动。本地 ArkTS/HAP 编译通过。手机已暂时拔掉，**尚未做本轮真机视觉与交互验收**；下一轮再考虑底部原生悬浮页签及其系统沉浸光感。
- **第 3 步 ArkUI 界面进行中**：第 2 步已提交（`e35f989`）。验证页改成原生深色玻璃风格三页界面：概览页控制 VPN/模式、代理页展示组与节点并测速、配置页支持 URL 或 YAML 导入/更新/切换。采用 ArkUI `backgroundBlurStyle`、半透明卡片与原生系统栏配色；按 UI/UX 规范保持高对比文字和大触控区域。HAP 已编译并在 Mate 70 Pro 安装成功；概览和配置页已截图核对布局、系统栏、底部导航、文字可读性。**完整交互与代理页仍待验证**；真机当前又启用了其他 VPN（`vpn-tun` 为 `10.0.0.254`），复测本应用连接前需由用户暂时关闭。验证后再提交第 3 步。
- **第 2 步真机验证通过**：用户关闭原有 VPN 后，安装最新 HAP、启动并授权本工程 VPN，`vpn-tun` 为 `172.19.0.1/30`，界面显示「TUN 已连接」。mihomo `/connections` 出现其他应用的 `Tun` 连接和持续增长的上下行流量；通过 `hdc` 唤起手机浏览器访问 IANA 页面，页面内容成功加载。带 secret 的 `/version` 返回 mihomo 1.10.0，未授权 REST 请求返回 401。
  - **已知限制**：连接 UID 可查到，但 `bundleManager.getBundleNameByUidSync` 对其他应用返回权限错误 201，因此 `/connections` 暂无应用包名。TUN 联网不受影响；后续分应用代理前需研究系统权限/替代接口。
  - 下一步：提交第 2 步，再做第 3 步 ArkUI 界面（订阅、代理组/节点、延迟、模式、VPN 控制）。
- **第 2 步继续推进（本次）**：
  - 新增 `api/MihomoApi.ets`：带 Bearer secret 的 REST 客户端，覆盖版本、配置/模式、代理组、节点选择与延迟测试。
  - 新增 `profile/`：`ProfileStore` 支持粘贴 YAML、URL 导入/更新、活动订阅与 `subscription-userinfo`；`RuntimeConfig.ts` 用 `yaml@2.8.0` 合成运行配置；`SecretStore` 首次生成 32 字节随机 secret 保存在应用私有目录。验证页改用这些模块生成 `config.yaml` 并查询版本。
  - 修复 VPN 创建失败后的 TUN/监听清理。HAP 编译、签名、安装成功；真机上带 secret 的 `/version` 返回 mihomo 1.10.0，Mac 经 `hdc fport` 不带 secret 请求 `/version` 和 `/configs` 均返回 401。配置合成与 YAML 校验在本机通过针对性检查。
  - `hdc kill` 后 `hdc start` 重新发现 Mate 70 Pro。真机 TUN 验证仍被已有 VPN 阻挡：`VpnConnection.create()` 返回 `2203002`；系统现有 `vpn-tun` 地址为 `10.0.0.254`（本工程配置为 `172.19.0.1`）。已请用户在手机上暂时关闭现有 VPN，未主动中断它。
  - 当时的待办已在上条完成；唯独包名识别受系统权限限制。
- **第 2 步进行中（今天收工时的状态）**：
  - 已写完、**已编译通过、未在真机测试、未提交**（都在 main 的工作区里）：
    - `entry/src/main/ets/vpn/VpnProtocol.ets`：IPC 约定（START/STOP/STATUS，JSON 进出；`VpnOptions`、`StartParams`、`VpnStatus`）。
    - `entry/src/main/ets/vpn/VpnExtAbility.ets`：内核运行处。`onRemoteMessageRequest` 用 async 直接写 reply（不用回调 stub）；start = quickSetup → `vpnConnection.create` 拿 fd → `startTUN`（stack 默认 mixed，DNS 默认全劫持）→ 订阅 NetworkManager(updateDns)/PowerManager(suspend)。
    - `entry/src/main/ets/vpn/VpnClient.ets`：界面侧，`startVpnExtensionAbility` + `connectServiceExtensionAbility`，同步 sendMessageRequest。
    - `NetworkManager.ets`、`PowerManager.ets`、`Network.ets`：照搬参考项目。
    - `module.json5`：注册 `type: "vpn"` 的 VpnExtAbility；加 `GET_NETWORK_INFO`、`GET_BUNDLE_INFO` 权限。
    - `pages/Index.ets`：验证页改为 启动 VPN / 停止 VPN / 查询状态 / 查询版本；界面进程不再 import core。临时配置是直连 + fake-ip DNS，还没有 secret。
  - REST 客户端（`entry/src/main/ets/api/MihomoApi.ets`）和订阅/运行配置模块（`entry/src/main/ets/profile/`：ProfileStore、RuntimeConfig、secret）**还没写**：派出的 agent 在查完资料、动手写代码前因额度问题被停掉，没有留下文件。要求见 architecture.md 的决策记录（覆盖项、DNS 默认值、secret、YAML 用 ohpm `yaml` 放进 `.ts`）。
  - 卡在真机连接：手机 USB 掉线后 hdc 一直列不出设备（详见 dev-guide「踩过的坑」）。
- **下次接着做**：
  1. 恢复 hdc 连接（拔线 → 开发者选项里 USB 调试关了再开 → 重插；或用无线调试 `hdc tconn IP:端口`）。
  2. 装上验证 VPN：点「启动 VPN」→ 手机上允许 VPN 授权 → 手机浏览器打开网页 → Mac 上 `hdc fport tcp:19090 tcp:9090` 后查 `/connections`，能看到其他应用的连接（带包名）即 TUN 打通。
  3. 写 api/ 和 profile/ 模块，验证页改为用 RuntimeConfig 生成配置并带 secret 访问 REST。
  4. 第 2 步验证通过后提交，然后开始第 3 步界面。
- **第 1 步完成**（commit 478ee58）：
  - 装好 ohos 版 Go 1.24.5，交叉编译出 `libclash.so`。
  - 搭好 DevEco 工程（`entry` + `core`），命令行编译、签名、安装都打通。
  - Mate 70 Pro 上内核（mihomo 1.10.0 meta）在界面进程里启动成功：`/version`、`/configs` 正常；Mac 经 `hdc fport` 走手机 mixed-port 7890 访问 https 返回 200。
