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

稳定发布至少覆盖最低支持 macOS 与当前最新稳定 macOS，以及两个 Apple Silicon 芯片代际。未验证的新 macOS 大版本只能标为“未验证”，不得自动包含在“或更高版本”的支持承诺中。

### FR-5：证据产物

每次发布生成机器可读 `release-evidence.json` 和人类可读报告，包含：版本、tag、commit、构建主机、Xcode/Swift、macOS、DMG hash、guest identity、QEMU 版本、测试结果、E2E 设备矩阵、已知限制和批准人。不得包含证书私钥、路径中的用户名或其他敏感信息。

### FR-6：发布源统一

DMG、源码、Release notes、Issue 和 checksum 只能发布到 `superops-team/my-omarchy`。产物命名为 `MyOmarchy-<version>-arm64.dmg`。

## 4. 实现方案

### 4.1 门禁分层

- PR CI：确定性单元、契约、静态兼容性与脚本测试。
- Release build：在受控 Apple Silicon 构建机执行完整重建、签名和公证。
- Device qualification：在真实设备矩阵安装最终 DMG 并产生 E2E 记录。
- Publish：仅当三层均为 pass 时允许上传 GitHub Release。

### 4.2 E2E 可重复性

自动化负责环境采集、日志、启动、SSH/共享目录/网络/磁盘等可编程检查；摄像头权限、跨屏和人眼显示质量采用明确步骤的人工验证。所有人工项必须记录执行者、设备和结果，不能只勾选 Markdown。

### 4.3 发布可追溯性

App 的 `CFBundleShortVersionString` 来自 semver tag，`CFBundleVersion` 来自单调递增构建号；两者与 guest provenance 一起嵌入 App。最终 checksum 对公证后的 DMG 计算。

## 5. 边界情况

| 场景 | 处理方式 |
|------|----------|
| CI 通过但真实设备失败 | 阻断发布，保留失败证据 |
| Apple 公证服务临时失败 | 不降级生成未公证产物；允许同一输入重试 |
| 构建缓存命中 | release 强制重建，缓存仅用于下载输入且必须校验 hash |
| 最新 macOS 尚无设备 | 缩窄支持声明，不伪造兼容结论 |
| 工作区存在未提交文件 | preflight 立即失败 |
| E2E 需要隐私权限 | 使用专用测试用户并记录授权状态，不复用开发者授权 |

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
4. 从 GitHub Release 下载的 DMG 在干净测试用户下完成首次启动。
5. E2E 清单中的全部 P0 路径在支持矩阵设备通过。
6. Release 页面包含 DMG、SHA-256、源码 commit、已知限制和验证报告。
7. `release-evidence.json` 可由 CI 校验且不泄露敏感信息。
8. README 不再保留与实际证据冲突的“尚未验证”或过宽支持声明。
