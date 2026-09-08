# My Omarchy 发布质量门禁设计文档

## 1. 概述

### 1.1 问题

当前 CI 主要运行静态契约和单元测试，真实 QEMU VM、最终签名 DMG、macOS 权限、HiDPI、音视频、睡眠唤醒与外置盘行为仍依赖人工清单。`make release` 也没有强制 clean tree、测试、tag/版本一致性、Gatekeeper 和最终 DMG 回装验证。

### 1.2 目标

建立一个不可绕过、证据可追踪的 My Omarchy 发布门禁，使公开 Release 中的每个 DMG 都能映射到唯一 tag、commit、guest identity、测试矩阵和真实 Mac 验证报告。

## 2. 用户场景

### 场景 1：维护者发版

**Given** 维护者位于 release tag 的干净工作树

**When** 执行唯一 release 命令

**Then** 系统完成测试、强制构建、签名、公证、Gatekeeper、回装验证和 checksum 生成，任一阶段失败均不产生可发布状态

### 场景 2：用户验证下载物

**Given** 用户从 `superops-team/my-omarchy/releases` 下载 DMG

**When** 用户核对 checksum 和 App 版本

**Then** DMG SHA-256、tag、App 版本、commit 和 provenance 一致

## 3. 功能需求

### FR-1：单一发布入口

仓库只提供一个正式 release gate。该入口必须拒绝：dirty tree、非 `main` 祖先、非 semver tag、tag 与 App 版本不一致、缺少签名身份、缺少 notary profile、缓存产物无法证明来源。

### FR-2：自动化构建门禁

release gate 顺序固定为：

1. toolchain doctor；
2. Git 与版本 preflight；
3. 完整测试；
4. `FORCE=1` 的 guest/runtime/app clean rebuild；
5. bundle 内容与架构验证；
6. Developer ID 签名；
7. notarization 与 staple；
8. `spctl --assess`；
9. 挂载最终 DMG，重新验证其中 App；
10. 启动 smoke test；
11. 生成 checksum 与 provenance；
12. 关联真实 Mac E2E 证据。

`doctor` 必须验证 Swift `Testing` 模块可编译，而不只是检查 `swift` 可执行文件存在。

### FR-3：真实 Mac E2E

最终签名 DMG 必须在真实 Apple Silicon Mac 完成可重复的半自动或自动 E2E：

- 全新安装与首次 owner provisioning；
- App 重启、guest reboot、guest shutdown；
- Mac sleep/wake；
- 窗口缩放和跨 HiDPI 显示器；
- 键盘、Command/Super、鼠标和输入法；
- 音频播放、麦克风、运行中切换输出设备；
- 摄像头按需启停；
- 文本和 PNG 双向剪贴板；
- 共享目录双向读写；
- TCP/UDP 转发和 SSH preset；
- 持久、ephemeral、Factory Reset；
- 自定义/外置 APFS 位置与异常断开。

### FR-4：支持矩阵

发布门禁分为两个 profile：

- `prerelease`：至少一台列入支持清单的真实 Apple Silicon Mac 通过全部 P0 E2E；Release 必须标记 prerelease，并逐项列出尚未验证的 macOS、芯片代际和功能限制。
- `stable`：最低支持 macOS 与当前最新稳定 macOS 均通过，且至少覆盖两个 Apple Silicon 芯片代际；全部 P0 E2E 和适用于稳定版的专题门禁必须通过。

未验证的新 macOS 大版本只能标为“未验证”，不得自动包含在“或更高版本”的支持承诺中。稳定版的同一台设备可以同时满足一个 macOS 版本和一个芯片代际维度，但完整矩阵不得少于两台物理设备。

### FR-5：证据产物

每次发布生成机器可读 `release-evidence.json` 和人类可读报告。JSON 使用版本化 schema，至少包含：`schemaVersion`、`gateProfile`、`candidateId`、版本、tag、commit、构建号、构建主机类别、Xcode/Swift、macOS、DMG SHA-256、guest/factory digest、QEMU 版本、测试结果引用、E2E 设备矩阵、已知限制、生成时间和批准人。不得包含证书私钥、路径中的用户名或其他敏感信息。

证据必须绑定不可变 candidate 和精确 DMG digest。最终证据以 GitHub artifact attestation 或等价的项目签名机制签署；CI 必须验证 schema、签名、仓库身份、tag/commit、candidate ID 和 digest 一致，单独替换 JSON 或 DMG 均会失败。

### FR-6：发布源统一

DMG、源码、Release notes、Issue 和 checksum 只能发布到 `superops-team/my-omarchy`。产物命名为 `MyOmarchy-<version>-arm64.dmg`。

## 4. 实现方案

### 4.1 门禁分层

- PR CI：确定性单元、契约、静态兼容性与脚本测试。
- Release build：在受控 Apple Silicon 构建机执行完整重建、签名和公证。
- Candidate staging：为公证后的最终 DMG 生成 `candidateId` 和 SHA-256，并上传到 `superops-team/my-omarchy` 的 GitHub Draft Release；Draft 不作为公开下载或支持入口。
- Device qualification：从 Draft Release 下载该 candidate，在 gate profile 要求的真实设备矩阵安装并产生 E2E 记录。
- Publish：仅当 PR CI、Release build 和对应 gate profile 的 Device qualification 均为 pass 时，将同一个 Draft Release 和同一 digest 的 DMG 提升为公开 prerelease 或 stable Release。qualification 后禁止重新构建、重新签名、重新打包或替换 DMG。

候选成功状态固定为 `built -> staged -> qualifying -> qualified -> published`；`built` 到 `qualifying` 的任一状态均可转为终态 `rejected`，但 `rejected` 不能转为 `published`。失败 candidate 保留失败证据但不得发布；重试构建必须生成新的 `candidateId`。

### 4.2 E2E 可重复性

自动化负责环境采集、日志、启动、SSH/共享目录/网络/磁盘等可编程检查；摄像头权限、跨屏和人眼显示质量采用明确步骤的人工验证。所有人工项必须记录执行者、设备和结果，不能只勾选 Markdown。

### 4.3 发布可追溯性

App 的 `CFBundleShortVersionString` 来自 semver tag。`CFBundleVersion` 的唯一权威来源为受保护 release workflow 的 GitHub Actions `run_number`，以十进制字符串写入；本地只能构建非发布产物，不能分配正式构建号。release preflight 必须验证同一仓库内 tag、commit、构建号组合唯一且构建号高于已有公开 Release。两者与 guest provenance 一起嵌入 App。最终 checksum 对公证后的 DMG 计算。

### 4.4 发布状态与制品不变性

release workflow 创建 Draft Release 后，记录 asset API 返回的 asset ID、size 和 SHA-256。真实设备 runner 必须通过 Draft asset 下载，不能使用构建机工作目录副本。Publish 阶段重新下载并校验相同 asset；只有 asset ID、size、digest、签名和公证票据全部一致时才允许改变 Release 可见性。

## 5. 边界情况

| 场景 | 处理方式 |
|------|----------|
| CI 通过但真实设备失败 | 阻断发布，保留失败证据 |
| Apple 公证服务临时失败 | 不降级生成未公证产物；允许同一输入重试 |
| 构建缓存命中 | release 强制重建，缓存仅用于下载输入且必须校验 hash |
| 最新 macOS 尚无设备 | 缩窄支持声明，不伪造兼容结论 |
| 工作区存在未提交文件 | preflight 立即失败 |
| E2E 需要隐私权限 | 使用专用测试用户并记录授权状态，不复用开发者授权 |
| qualification 后发现需要修复 | 拒绝当前 candidate；修复后从 clean build 生成新 candidate，不替换原 asset |
| Draft asset 无权被测试设备读取 | 使用最小权限 GitHub token 下载；不允许回退到未经 digest 绑定的临时文件 |

## 6. 涉及文件

- `.github/workflows/*`
- `Makefile`
- `macos/build-app.sh`、`macos/package-dmg.sh`、兼容性验证脚本
- 新增 release preflight、evidence 和 E2E 脚本
- `docs/releasing.md`、README 支持矩阵
- `macos/Info.plist` 和 provenance 生成逻辑

## 7. 验收标准

1. dirty tree、错误 tag、版本不一致、缺少 `Testing` 模块均在构建前失败。
2. release 命令强制执行完整测试和 clean rebuild。
3. 最终 DMG 通过 codesign、notary、stapler、Gatekeeper 和挂载后 App 复验。
4. qualification 从 GitHub Draft Release 下载 DMG；发布后再次从公开 GitHub Release 下载，并验证二者 asset ID、size 和 SHA-256 对应同一 candidate。
5. `prerelease` 在至少一台已登记设备通过全部 P0 E2E；`stable` 在最低/最新 macOS 和至少两个 Apple Silicon 代际的完整矩阵通过。
6. Release 页面包含 DMG、SHA-256、源码 commit、已知限制和验证报告。
7. `release-evidence.json` 通过版本化 schema、签名/attestation、candidate identity 和 artifact digest 校验，且不泄露敏感信息。
8. README 不再保留与实际证据冲突的“尚未验证”或过宽支持声明。
9. qualification 后任何 asset 替换、重新打包或 digest 漂移都会阻断 Publish。
