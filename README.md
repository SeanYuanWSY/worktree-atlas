# Worktree Atlas

**把工作树放回图里。** 一个以工作树为中心的原生 macOS 应用：多个仓库同屏，工作树直接标在真实 Git 提交图上。

[公开仓库](https://github.com/SeanYuanWSY/worktree-atlas) · [English](README.en.md) · [架构](docs/ARCHITECTURE.md) · [本机验收](docs/LOCAL_TEST.md) · [验证记录](docs/VALIDATION.md) · [开发交接](AGENTS.md)

> **状态：0.1.0-dev，本机与 GitHub 构建验证通过，源码已公开。** 已在 Apple Silicon Mac 上编译、签名并打开原生应用，用临时 Git 仓库验证双仓库图谱、新建、锁定、解锁、移除和失效记录清理。纵向界面改版的本机及[GitHub Mac 构建](https://github.com/SeanYuanWSY/worktree-atlas/actions/runs/36327521805)均实际运行 49 项测试并全部通过；详细范围见[验证记录](docs/VALIDATION.md)。GitHub 仓库 `SeanYuanWSY/worktree-atlas` 为公开仓库。

## 界面方向

当前原生界面参考 GitLens 提交图的密集表格排版：深灰黑底色、左侧真实分叉线、紧邻的分支／工作树标签，以及按列对齐的提交标题、作者、相对时间和短 SHA。未提交变更单列在图上方；点击标题查看完整正文，点击工作树打开详情。多个仓库以可折叠的纵向面板同屏管理。只借鉴图谱排版，不集成 GitLens 功能或素材。

`docs/preview.html` 和两张预览图是首版横向设计的历史材料，**不代表当前原生界面**；以实际运行的 macOS 应用为准。

## 产品边界

不是完整 Git 客户端，不是 AI 代理管理器，也不是一个工作树路径列表。

首页按仓库显示独立图形卡片。提交连线描述真实的父提交关系，工作树作为 HEAD 上的标记。多个工作树可位于同一提交；合并关系不是“工作树父子关系”。

## 已实现的源代码

| 能力 | 行为 |
| --- | --- |
| 多仓库总览 | 同屏图形卡片、搜索仓库/路径/工作树、仅待处理筛选、单仓库聚焦 |
| 纵向提交图 | 逐行展示**已载入**提交、真实分叉／合并线、HEAD 标签、未提交变更、标题、作者、相对时间和短 SHA；长历史分页，正文点开查看 |
| 工作树信息 | branch / HEAD / path / clean / dirty / unknown / detached / locked / ahead / behind |
| 创建 | 新分支、已有分支或 detached；拒绝覆盖已有目录 |
| 安全移除 | 保留分支；拒绝主工作树、锁定、未知、有修改、未跟踪或被忽略文件的目录；保护无分支/标签保留的游离提交 |
| 保护与清理 | 锁定 / 解锁；失效记录先预览再确认清理；不自动清理离线磁盘 |
| 外部工具 | Finder、Terminal、VS Code、Cursor、Xcode；复制路径 |
| 自动更新 | 前台定时轮询本地 Git，支持暂停；同一轮最多两个仓库并发扫描 |
| 本地体验 | SwiftUI、浅色/深色、键盘菜单、设置窗口、纯内存演示模式 |

不会执行 commit、push、pull、fetch、merge、rebase、cherry-pick、分支删除或强制移除。不会自动启动终端、安装依赖或调用模型。`only worktree` 指操作范围；图中仍保留理解工作树位置所需的提交与分支上下文。

## 在 Mac 上启动

要求：macOS 14+、Swift 6 工具链，以及支持 `git worktree list --porcelain -z` 的 Git（建议 Git 2.36+）。本机 Command Line Tools 可构建应用并运行 Swift Testing 测试。Apple Silicon 已实机运行，Intel 尚未验证。

```bash
cd /path/to/worktree-atlas
./script/build_and_run.sh
```

脚本构建本项目 `dist/WorktreeAtlas.app`、进行本地 ad-hoc 签名，再通过 `open` 启动。不会自动安装到 `/Applications`，也不会关闭 Gatekeeper。

```bash
./script/build_and_run.sh --demo       # 不读写你的仓库，使用内存演示
./script/build_and_run.sh --verify     # 额外检查进程是否存在，不代替 UI 验收
./script/build_and_run.sh --logs       # 启动后显示该进程的系统日志
./script/build_and_run.sh --build-only
```

Codex 的 Run 操作已经写入 `.codex/environments/environment.toml`。首次测试先用演示与临时仓库，不要直接在唯一副本上测试移除。

## 测试

```bash
./script/check.sh
./script/create_fixtures.sh
```

检查脚本会执行至少 48 项 Swift Testing 测试、构建原生应用，并拒绝“成功退出但实际运行 0 项测试”。Command Line Tools 环境下不要用裸 `swift test` 的退出码判断测试通过。

测试临时目录由 `mktemp` / UUID 创建，不接受要删除的用户路径。图测试还包含 80 个确定性生成 DAG 的节点间可达性比较。

可在 Linux 上用同一核心进行只读诊断：

```bash
swift run atlas-inspect /path/to/repository
swift run atlas-inspect --demo
```

诊断会打印本地路径和分支名。分享输出前请脱敏。

## 发布到 GitHub

公开仓库：[SeanYuanWSY/worktree-atlas](https://github.com/SeanYuanWSY/worktree-atlas)。首次发布使用了：

```bash
./script/publish_github.sh
```

脚本只接受已登录的 `SeanYuanWSY` 账号，固定提交项目的 54 个源文件，创建公开仓库并仅推送 `main`；拒绝覆盖已有仓库、更换已有 origin 或向父级仓库写入，不使用 force push。该脚本只用于首次发布，不要在已创建的仓库重复运行；后续开发按普通 Git 提交流程进行。

## 打包

```bash
./script/package_release.sh
```

在 Mac 生成当前 CPU 架构的开发版 DMG。可通过 `SIGN_IDENTITY` 使用自己的 Developer ID；Apple 公证是独立步骤，没有证书和实际提交就不能声称已公证。两个 Actions 工作流用于 macOS 构建测试及手动打包，不自动发布 Release。

## 必须知道的限制

- 图仅表示**已载入**历史。默认一次载入 1200 个提交，并补取被截断的工作树 HEAD；虚线表示更早历史未载入，不能据此推断仓库没有更早合流。
- ahead/behind 使用本地缓存的 upstream 引用，不代表刚向服务器查询的结果。
- 全仓库读取、引用与 worktree 状态不是原子快照；其他进程同时变更时会在后续刷新收敛。执行写操作前会重新检查，但不声称消除所有跨进程竞态。
- 轮询不是 FSEvents 实时推送。默认仅前台每 10 秒刷新，可修改为 5 / 30 / 60 秒。
- 非 UTF-8 Git 输出明确报错，不猜测路径编码。子模块/超大仓库可能使状态读取超时；未知状态不会被当成干净。
- 已登记的仓库或工作树目录若在同一路径被替换，会停止相关写操作；确认新目录可信后需在应用中明确重新添加仓库。旧版登记缺少目录身份时也需重新添加。
- 创建 worktree 需要检出文件，可能执行受信仓库中已配置的 Git 内容过滤器；UI 要求明确确认信任。
- 工作树移动、重命名、远程机器聚合、任意历史分页和完整 Git 写操作不在此开发版范围内。
- `docs/preview.html` 是旧版离线设计预览，不是当前原生界面、macOS 实机截图或第二套生产应用。

## 来源与许可证

基于 [GitScope](https://github.com/Oreo992/GitScope) 的部分模型、布局算法及扫描器架构继续开发，**不是官方 GitScope 版本**。具体来源、固定 commit 与修改范围见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。MIT；保留原作者版权声明。本项目首版采用 AI 辅助实现，所有测试状态以实际验证记录为准。
