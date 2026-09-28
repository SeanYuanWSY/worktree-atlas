# 实际验证记录

日期：2026-09-24。交付版本：0.1.0-dev。

本文件记录实际执行结果，不把源代码存在、Swift 语法解析、网页预览或 CI 配置等同于 macOS 应用可运行。

## 2026-09-27 编辑器式界面重做（当前）

- 【转述】用户否决上一版仍有较大卡片留白的样式，要求进一步按 GitLens 截图的界面比例重做。
- 【已核实】原生界面已改为窄活动栏／工作区侧栏、贴边连续仓库区域、22pt 提交行、17pt 轨道间距、细圆环节点、短弯折连线及紧凑分支标签。主工作树第一父提交链固定在左轨；WIP 行紧邻对应 HEAD。姓名首字母作为作者标记，SF Symbols 作为图标。
- 【已核实】演示数据扩展为三个仓库、十二个工作树，每仓库 48 条提交，含分叉和真实父子关系定义的合并节点。在原生窗口检查了多仓库总览、单仓库聚焦、第二页剩余 8 条历史和延续虚线、提交正文弹窗、工作树详情，以及选中行不遮挡图节点。标签宽度改用实际字体测量，修复普通分支名无故截断。
- 【已核实】修订后的 `./script/check.sh` 退出码 0，49 项 Swift Testing 测试和原生构建／签名／plist 检查通过；新版 `.app` 已重新启动。独立定点复核未发现阻止发布的问题。精确窄窗口尺寸、极长名称与真实大仓库边界仍以 `LOCAL_TEST.md` 未勾选项为准。
- 【已核实】源码提交 `02204a1` 已推送到公开仓库；[GitHub macOS 运行 36331382509](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/36331382509) 结论为 `success`，日志显示 49 项测试通过，原生开发包上传成功。

## 2026-09-27 GitLens 风格提交表改版（已被上方版本替代）

- 按本轮用户提供的 GitLens 截图重新设计原生多仓库总览：单列可折叠仓库面板，每仓库一张密集提交表，左侧为真实提交分叉线，右侧依次为工作树／分支、提交标题、作者、相对时间与短 SHA。工作树有未提交变更时另列顶部状态行。提交正文仍在点击标题后完整查看。没有复用 GitLens 图标、代码或附加功能。
- 在本机真正的 macOS 应用演示窗口目视核对三仓库、九工作树、分叉线、未提交行、列对齐及 `main` 标签完整显示。点击工作树和提交标题的原生交互已检查。演示提交时间改成相对当前时间，便于检验时间列。
- `./script/check.sh` 退出码 0：49 项 Swift Testing 测试、3 个 suite；原生应用构建、签名和 plist 检查通过。`./script/build_and_run.sh --demo` 已重新启动新版窗口。提交 `1909969` 的 [GitHub macOS 构建](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/36329694140) 结论为 `success`：远端日志显示 49 项测试通过、原生应用归档与开发版 artifact 上传成功。
- 发布前复核修正了分页边界无提示断线、未知或失效工作树被误称为未提交变更、同一 HEAD 的其余工作树被藏在菜单，以及未载入 HEAD 无法点击的问题。跨页连线现在以虚线延续并在页脚解释；同一行的多个工作树及引用可水平浏览。以上修订后再次运行 `./script/check.sh`，49 项测试与原生构建均通过。

## 2026-09-27 纵向界面改版

- 根据用户反馈，将原生仓库卡片中的左右图谱改为自上而下的真实提交图。提交行显示标题、实际提交时间、作者、短 SHA 和正文摘要；可打开完整正文，工作树仍固定在其真实 HEAD 节点。保留多仓库图卡、单仓库聚焦、完整已载入历史分页和状态详情。
- 深色模式改用近黑背景、深色卡片与低亮度青色分隔。演示模式原生窗口已目视检查：三张仓库卡片可见，点击 `feature/graph` 打开正确工作树详情；完整正文弹窗、单仓库聚焦、完整已载入历史切换正常。浅色模式也已打开目视检查，并恢复深色设置。超过 30 条历史的分页边界提示尚未在原生窗口目视检查。
- 旧 `docs/preview.html` 与预览图片保持历史材料身份，已在 README 标明不代表当前原生界面。
- `./script/check.sh` 在本机重新通过：**49 项 Swift Testing 测试、3 个 suite**，包含对真实临时 Git 仓库的提交正文与提交时间读取；SwiftUI 原生构建、ad-hoc 签名、plist 及脚本检查通过。`./script/build_and_run.sh --demo` 已打开新版应用。改版源码提交 `05ca585` 的 [GitHub macOS Actions 运行 36327521805](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/36327521805) 已结束且结论为 success；远端日志实际显示 **49 项测试通过**，原生应用构建、开发版归档与上传均成功。

## 本次 macOS 实机验证

- macOS 26.4.1、Apple Silicon arm64、Swift 6.3.1、Git 2.50.1；开发目录是 `/Library/Developer/CommandLineTools`。未安装完整 Xcode，`xcodebuild -version` 因此失败。
- 桌面源码包 `WorktreeAtlas-0.1.0-dev-source.zip` 已核对结构后解压到本工程目录。ZIP 本身不含 `.git`；初次本机验收时尚未初始化 Git checkout，因此当时无法运行 `git diff --check`。
- 发布准备阶段，当前登录的 GitHub 账号 `SeanYuanWSY` 及可见的两个组织仓库中均未找到 Worktree Atlas；`gh api repos/SeanYuanWSY/worktree-atlas` 返回 HTTP 404。用户随后明确确认没有现有仓库，并授权新建该公开仓库。
- `swift build --product WorktreeAtlas` 通过，SwiftUI / AppKit 在本机完成类型检查和链接。`./script/build_and_run.sh --demo` 构建应用、图标并 ad-hoc 签名；`codesign --verify --strict` 与 plist 检查通过，原生窗口实际打开。
- 最初的 XCTest 版测试在本机 Command Line Tools 下因 `no such module 'XCTest'` 中断。随后迁移为 Swift Testing，并让 `./script/check.sh` 在本机显式加载 CLT 的 Testing 运行库、检查实际测试数量。最终整套检查退出码 0：**48 项测试、3 个 suite 全部通过**，Swift/脚本语法检查及原生应用构建和签名通过。裸 `swift test` 在此 CLT 环境可退出 0 却运行 0 项，不作为本机验收入口。
- 使用 `./script/create_fixtures.sh` 创建多套一次性真实 Git 仓库。原生应用曾同屏显示两个独立图卡，共 7 个工作树；两卡节点均显示 branch、短 HEAD、状态和锁定信息，点击节点能打开对应路径、完整 HEAD 与状态详情。最终修订版也重新完成真实仓库导入与操作检查；系统文件选择器的“打开”按钮在未选中目录时置灰，选中目录后正常启用。
- 在第一套临时仓库中，通过应用锁定并解锁 `feature/parser` 工作树；再通过确认对话框移除该干净工作树。核对工作目录已不存在，而同名分支仍保留。脏工作树的移除按钮在界面中不可用。
- 最终修订版在另一套独立临时仓库中经原生 UI 新建 `feature/ui-check`，图卡从 4 个工作树增至 5 个；锁定后标记及 Git porcelain 均出现锁信息，移除按钮禁用，解锁后恢复。UI 移除干净工作树后目录消失、分支仍保留。失效记录清理先展示与 Git dry-run 一致的单条预览，确认后只清掉该记录，其他 4 个工作树和测试文件仍在。应用重启后临时仓库登记仍在；最终已从总览移除，持久登记数组为 `[]`。
- 演示数据的 3 张仓库图卡、浅色与深色原生窗口及详情面板已目视检查；最终构建的演示卡片显示不同的短 HEAD。系统半屏窗口约 871×768 时图谱与四个工作树标签仍可见，恢复窗口尺寸正常。指定的 1380×880 与 980×660 尺寸、Intel Mac、VoiceOver 和极大仓库尚未逐项验证。
- `atlas-inspect` 在第一套真实临时仓库上输出 4 个工作树、4 个节点、3 条边；包含 1 个有修改的工作树。
- 工作树目录被符号链接或同路径复制替换时的拒绝逻辑，已用额外的一次性 Git 仓库执行验证；正常锁定、解锁、移除仍成功。登记记录现在持久保存仓库及工作树的设备号/inode；刷新、重启和路径复用不会自动信任替换目录，明确重新添加才会重绑。相关回归测试已包含在 48 项通过的 Swift Testing 测试中。独立安全复核未发现剩余的实质缺陷；最终检查与 Git 执行之间仍有外部写者竞态。

本次修改还补上了 Swift 6.3 下 Git 解析器的编译问题、图节点的 HEAD/状态标记、窗口宽度变化时的图适配、演示数据短 HEAD，以及仓库身份和脚本防护。最终原生应用已在这些改动后重新构建与打开；Swift 与 Shell 语法检查、签名及 plist 检查通过。公开发布前复核已恢复上游版权原行、移除文档中的个人绝对路径、将新仓库发布脚本限定为固定 54 个文件与单分支推送；GitHub 创建和推送以执行后的远端记录为准。

## GitHub 发布核验

- 已创建并推送公开仓库：`https://github.com/SeanYuanWSY/worktree-atlas`。GitHub 返回可见性 `PUBLIC`、默认分支 `main`。
- 首个提交为 `0b2296c4eba54274f982c8a19b5c8091d8bde855`；`git ls-remote origin refs/heads/main` 与本地 HEAD 一致。GitHub 树接口与本地提交树均为 54 个文件。提交的作者和提交者均为该 GitHub 账号的 noreply 身份。
- 初次推送触发的 [macOS Actions 运行 35975786842](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/35975786842) 已实际结束，结论 `success`。运行器为 Xcode 16.4 / Swift 6.1.2，日志显示 **48 项测试通过**、原生应用构建成功、开发版 ZIP 打包与上传成功。产物 `WorktreeAtlas-macOS-ARM64-development` 是 CI 开发包，并非 Developer ID 签名或公证的正式发行版。

## 前期 Linux 交付环境与记录

- Linux x86_64；Swift 6.2.1，目标 `x86_64-unknown-linux-gnu`；Git 2.47.3。
- 不包含 macOS SDK、SwiftUI 或 AppKit；不能在此环境完成 Mac 应用类型检查、链接或运行。
- GitHub 连接识别为 `SeanYuanWSY`，本轮已提供的接口均为读取操作，没有创建仓库或推送接口。
- 本环境无已安装并认证的 GitHub CLI。发布脚本在依赖检查处退出，没有创建远端。
- 当时没有访问本机工程目录；此描述是前期 Linux 环境的历史记录。

## 已实际执行

| 检查 | 实际结果 |
| --- | --- |
| `swift build` | 通过，编译 AtlasCore 与 atlas-inspect；Linux 包条件不包含 SwiftUI 目标 |
| `swift test` | **42 项 XCTest 测试，0 失败** |
| 图投影 | 12 项图测试，含 80 个固定种子生成 DAG 的保留节点可达性检查 |
| Git 解析 | 10 项，覆盖中文、空格、换行路径、重命名、游离/空仓库及未知输出 |
| 真实 Git 集成 | 20 项，在 UUID 临时目录内创建真实仓库及工作树，无远程网络访问 |
| SwiftUI 源码 `swiftc -frontend -parse` | 语法解析通过；**不是** macOS API 类型检查或原生编译 |
| Shell 脚本 `bash -n` | 通过；不等于 macOS 打包或 GitHub 发布已执行 |
| Actions YAML / Codex TOML | 语法解析通过；CI 没有在 GitHub 上运行 |
| 离线 HTML 预览 | 在 Chromium 144.0.7559.96 中实际渲染及交互测试通过 |
| 非 Mac 打包入口保护 | `--build-only` 正确拒绝在 Linux 运行，退出码 1 |
| 发布入口依赖保护 | 缺少 gh 时正确停止，退出码 1，没有网络写操作 |

完整日志：[Linux 构建与测试](evidence/linux-check.log)。日志尾部 Swift Testing 显示的 “0 tests” 指没有使用该第二套框架；42 项实际测试属于前面的 XCTest，不能将两者混淆。

### 真实 Git 测试重点

创建新分支工作树、已有分支保持 attached、游离与空仓库、从 linked worktree 添加时去重、锁定/解锁、移除保留分支、拒绝未提交/未跟踪/被忽略文件、拒绝移除主工作树、保护没有本地引用保留的游离提交、失效路径清理预览变化时拒绝执行、旧工作树 HEAD 不因历史截断被遗漏，以及只读扫描前后索引和 HEAD 未改变。

临时测试通过不意味着消除了全部并发竞态、所有磁盘权限情形或所有 Git 版本差异。尤其忽略文件检查之后仍可能有外部进程写入新文件；移除前应停止工作树内的开发进程。

### HTML 预览的验证范围

[机器可读结果](evidence/html-preview-checks.json)。实际验证了 3 个仓库卡片、9 个工作树标记、搜索、无结果状态、详情打开/关闭、单仓库聚焦/返回、待处理筛选、浅色/深色、占位操作提示、1440px 与 980px 宽度无水平溢出，以及无 JavaScript 页面错误。

图的节点和连线数据来自编译后的 `atlas-inspect --demo`。网页绘制是设计表达，不等于 SwiftUI 像素级复现；预览图均标注“不是 macOS 实机截图”。

可选复现（需要 Python Playwright 和 Chromium，应用本身不依赖它们）：

```bash
python script/check_preview.py
```

## 仍未完成 / 不作承诺的部分

- 现有 48 项 Swift Testing 测试已在本机通过，但完整 Xcode 环境、GitHub Actions、Intel Mac 尚未实测。
- UI 新建工作树的“已有分支”和“游离 HEAD”模式，以及极长分支名、准确像素窗口尺寸、外部程序打开路径等仍待逐项验收。
- Intel 运行、VoiceOver、多窗口行为、指定最小窗口尺寸及压力测试。
- DMG、Developer ID 签名和 Apple notarization。当前 `.app` 仅为本机 ad-hoc 签名的开发包。
- 首个 GitHub Actions 运行已通过；后续提交仍须以各自远端运行的实际结论为准。原始源码 ZIP 本身不含 Git 元数据。
- 大型真实仓库、极多工作树、真实离线外接盘与持续并发变更的压力测试。

## 后续入口

项目代码位于本文件的上一级工程目录。继续用 `./script/check.sh` 验证，未勾选的原生验收见 [LOCAL_TEST.md](LOCAL_TEST.md)。公开仓库已创建；后续改动通过普通 Git 提交同步，不重复执行首次发布脚本。

## 2026-09-28 作者列与排版细节

- 【已核实】作者列显示固定颜色首字母头像及姓名，设置支持作者姓名、24/30pt 行距、相对/绝对日期；右键可复制 SHA 与标题。头像为本地姓名标识，未接入在线照片。
- 【已核实】原生窗口检查多仓库作者显示、行距与日期即时切换；修复表头与滚动内容的宽度差。姓名较长时截断并保留完整提示。
- 【已核实】本次本地检查通过 49 项测试及原生构建。
- 【未验证】本次未重测浅色、精确最小窗口和 VoiceOver；没有宣称与 GitLens 像素级一致。

## 2026-09-28 README 与原生截图

- 【已核实】重新构建并启动 `./script/build_and_run.sh --demo`。`docs/native-overview-dark.png` 来自只读演示模式的原生深色多仓库窗口；`docs/native-worktree-inspector-light.png` 来自本次构建应用的独立演示副本，在浅色模式聚焦 Atlas 并打开 `feature/graph` 详情。两图均只含虚构仓库与 `/demo` 路径，不是旧 HTML 预览。
- 【已核实】中英文 README 收敛为产品介绍、原生截图、功能、源码运行、安全范围与来源许可；开发验证和历史记录继续保留在本文件，不在 README 首页铺陈。
- 【已核实】改动后 `./script/check.sh` 退出码 0，49 项 Swift Testing 测试、原生构建、签名与 plist 检查通过；README 本地图片与文档链接检查通过。GitHub CI 以推送后的实际运行结果另行确认。
