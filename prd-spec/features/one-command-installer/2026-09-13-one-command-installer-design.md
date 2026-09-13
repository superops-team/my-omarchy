# My Omarchy 一键安装脚本设计文档

## 1. 概述

### 1.1 问题/背景

My Omarchy 当前以未使用 Developer ID 签名、未公证的 prerelease 形式发布。用户需要手动下载 DMG、拖动 App，并在终端执行 `xattr -dr com.apple.quarantine`。这条路径步骤多、容易输错，也无法在安装前自动校验下载物是否与 Release 中声明的制品一致。

当前 v0.5.0 已公开发布以下资产：

- `MyOmarchy-0.5.0-arm64-unsigned.dmg`
- `MyOmarchy-0.5.0-arm64-unsigned.zip`

本功能为 GitHub README 与 Release 页面提供一条可复制执行的安装命令，由版本固定的 shell 脚本完成下载、校验、安装、解除 quarantine 和首次启动。

### 1.2 目标

- 用户只需复制并执行一条命令即可完成安装。
- 安装脚本、目标版本、资产名称和 SHA-256 必须相互固定，不通过 `latest` 或可变分支解析版本。
- 安装前验证平台、下载摘要、DMG 内容、Bundle ID、App 版本、架构和代码签名结构。
- 已安装版本升级时保留 `~/Library/Application Support/My Omarchy` 中的 VM 和用户数据。
- VM 运行中拒绝替换 App，不强杀 QEMU 或桥接进程。
- Accessibility 授权仍由用户在 macOS 系统设置中确认；脚本只负责打开对应页面。

### 1.3 非目标

- 不绕过 Developer ID 签名、公证或 Gatekeeper 的正式发布要求。
- 不静默授予 Accessibility、摄像头或麦克风权限。
- 不下载或执行 `main` 分支上的可变脚本。
- 不更新、重置、迁移或删除已有 VM。
- 不把 prerelease 描述为正式生产分发。

## 2. 用户场景

### 场景 1：首次安装

**Given** 用户使用 Apple Silicon Mac 和 macOS 15 或更新版本

**When** 用户从 README 或 v0.5.0 Release 页面复制一键安装命令并执行

**Then** 脚本下载固定版本 DMG、验证其 SHA-256、安装至 `/Applications/My Omarchy.app`、清除该 App 的 quarantine 属性并启动应用

### 场景 2：覆盖升级

**Given** `/Applications/My Omarchy.app` 已存在且 VM 没有运行

**When** 用户执行新版安装脚本

**Then** 脚本退出旧 App、原子化替换应用包，并保留应用支持目录中的 VM 数据与设置

### 场景 3：VM 正在运行

**Given** My Omarchy 的 QEMU 或 launcher/bridge 进程仍在运行

**When** 用户执行安装脚本

**Then** 脚本在下载或覆盖前停止，说明应先从管理界面安全关闭 VM，不发送强制终止信号

### 场景 4：下载物被替换或损坏

**Given** 下载的 DMG 摘要与脚本内固定值不同

**When** 脚本完成下载

**Then** 安装立即失败，临时文件被清理，现有 App 保持不变

### 场景 5：系统需要管理员权限

**Given** 当前用户不能直接写入 `/Applications`

**When** 脚本进入安装阶段

**Then** 通过 `sudo` 请求一次标准 macOS 管理员授权，并仅对明确解析的 App 目标执行复制、替换和 quarantine 清理

## 3. 功能需求

### FR-1：不可变安装入口

v0.5.0 页面使用：

```sh
curl -fsSL https://github.com/superops-team/my-omarchy/releases/download/v0.5.0/install-my-omarchy.sh | bash
```

README 的 Quick start 在每次发布时更新到当前明确版本。脚本 URL 不使用 `main`、`raw/main` 或 `/releases/latest/`。

### FR-2：版本与摘要绑定

发布资产 `install-my-omarchy.sh` 内固定：

- repository：`superops-team/my-omarchy`；
- version：`0.5.0`；
- DMG asset：`MyOmarchy-0.5.0-arm64-unsigned.dmg`；
- DMG SHA-256：`4bd2b39e66bcb7b952f5ea9d90ba85b48268f91295375c0b7257f451349801fa`；
- Bundle ID：`team.superops.myomarchy`。

脚本不得从 Release 正文、GitHub API 或远端 checksum 文件动态获取这些信任根。

### FR-3：安装前检查

脚本必须在改变系统前检查：

- 操作系统为 Darwin；
- 硬件架构为 `arm64`；
- macOS 主版本不低于 15；
- `curl`、`shasum`、`hdiutil`、`plutil`、`codesign`、`ditto`、`xattr`、`open` 等系统工具可用；
- 没有运行中的 My Omarchy QEMU、launcher 或 bridge 进程。

### FR-4：安全下载与校验

- 使用 `mktemp -d` 创建私有临时目录，并通过 `trap` 在成功、失败或中断时卸载 DMG、删除临时文件。
- `curl` 使用 HTTPS、失败即退出并跟随 GitHub Release 重定向。
- 下载后使用 `shasum -a 256` 对固定摘要进行比较。
- 摘要不一致时不得挂载、复制或修改现有 App。

### FR-5：DMG 与 App 身份校验

DMG 必须以只读、不自动打开方式挂载到脚本创建的明确挂载点。复制前检查：

- DMG 根目录恰有预期的 `My Omarchy.app`；
- App 不是符号链接；
- `CFBundleIdentifier` 等于 `team.superops.myomarchy`；
- `CFBundleShortVersionString` 等于脚本固定版本；
- 主可执行文件包含 `arm64`；
- `codesign --verify --deep --strict` 通过。

校验代码签名结构不代表 Developer ID 或公证验证。脚本输出必须继续明确这是 unsigned prerelease。

### FR-6：安全覆盖安装

- 如果 My Omarchy App 进程仍在而 VM 未运行，先通过 bundle identifier 请求正常退出，并等待退出完成。
- 安装目标固定为 `/Applications/My Omarchy.app`。
- 需要管理员权限时使用 `sudo`，不得把下载内容拼接进 shell 命令或 `eval`。
- 先复制到 `/Applications` 下的同卷临时路径，验证复制结果后再替换正式路径，避免复制中断留下半个 App。
- 若已有 App，先移动到同卷备份路径；新 App 安装并验证成功后删除备份。安装失败时恢复旧 App。
- 仅对新安装的 `/Applications/My Omarchy.app` 执行 `xattr -dr com.apple.quarantine`。
- 不读取、写入或删除 `~/Library/Application Support/My Omarchy`。

### FR-7：启动和权限引导

- 安装成功后通过 `open -a /Applications/My Omarchy.app` 启动 App。
- 输出中说明 Accessibility 权限不能由脚本静默授予。
- 打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`；如果该 URL 在当前系统不可用，只输出手动路径，不把安装判为失败。

### FR-8：README 与 Release 页面

- README Quick start 首先展示一键安装命令，并在其后保留手动下载说明作为回退。
- README 明确脚本作用、unsigned prerelease 限制、管理员授权原因和 VM 数据保留边界。
- v0.5.0 Release 上传 `install-my-omarchy.sh`，Release Notes 用同一条固定 URL 命令替换手工 `xattr` 主路径；手动方式保留为故障回退。
- 后续发版必须更新脚本内版本/摘要、README URL 和对应 Release Notes，不复用旧版本脚本。

## 4. 实现方案

### 4.1 仓库脚本

新增 `scripts/install-my-omarchy.sh`，采用 Bash 3.2 兼容语法并启用 `set -euo pipefail`。脚本不接受任意 URL、安装路径或 checksum 参数，减少把便捷入口变成通用下载执行器的风险。

脚本输出按 `检查环境 → 下载 → 校验 → 安装 → 启动` 展示简短阶段信息；错误信息写入 stderr 并返回非零状态。

### 4.2 安装事务

安装阶段使用固定路径：

```text
/Applications/.My Omarchy.installing.<pid>.app
/Applications/.My Omarchy.backup.<pid>.app
/Applications/My Omarchy.app
```

流程为：

1. 将已验证的挂载 App 复制到临时安装路径；
2. 再次验证临时安装路径；
3. 将现有 App 移动到备份路径；
4. 将临时 App 移动为正式目标；
5. 清除正式目标的 quarantine；
6. 最终验证成功后删除备份；
7. 任一步骤失败时恢复备份并清理临时路径。

所有提权文件操作通过一个受控函数执行，参数均作为独立 argv 传递。

### 4.3 发布资产

源码脚本与 v0.5.0 固定信息一起提交。实现完成并通过测试后：

1. 推送脚本与 README 提交；
2. 将精确提交中的脚本上传为 v0.5.0 Release asset；
3. 读取 GitHub 返回的 asset size/digest；
4. 更新 v0.5.0 Release Notes；
5. 从公开 URL 下载脚本并比较其 SHA-256 与仓库文件；
6. 使用隔离临时 Applications 根目录执行无提权测试，不覆盖真实安装。

v0.5.0 tag 不移动，现有 DMG/zip 不替换。安装脚本属于 Release 的补充资产，脚本自身记录目标 DMG 的既有不可变 digest。

### 4.4 测试接口

生产默认值固定且不可由命令行覆盖。为了测试不触碰真实 `/Applications`，脚本允许仅在显式 `MY_OMARCHY_INSTALLER_TEST_MODE=1` 时读取测试专用环境变量：

- 下载源替换为本地 fixture；
- 安装根替换为临时目录；
- 跳过实际 App 启动和系统设置跳转；
- 注入进程探测 fixture。

非测试模式下出现这些覆盖变量必须被忽略或拒绝，防止公开脚本被环境变量劫持到非 GitHub 下载源。

## 5. 边界情况

| 场景 | 处理方式 |
|------|---------|
| 非 macOS 或 Intel Mac | 下载前失败并说明系统要求 |
| macOS 低于 15 | 下载前失败 |
| GitHub 下载失败 | 保留现有 App，清理临时目录 |
| SHA-256 不一致 | 不挂载、不安装 |
| DMG 无预期 App 或 App 为符号链接 | 拒绝安装 |
| Bundle ID、版本或架构不匹配 | 拒绝安装 |
| 深度 ad-hoc 签名验证失败 | 拒绝安装 |
| VM 正在运行 | 不退出 App、不发送信号，提示先安全停止 VM |
| 管理 App 正在运行但 VM 已停止 | 请求 App 正常退出后继续 |
| 用户取消 sudo | 安装失败，现有 App 保持或恢复 |
| `/Applications` 空间不足 | 复制失败后恢复已有 App |
| 安装后 `open` 失败 | App 已安装，但脚本返回失败并给出手动启动路径 |
| 系统设置 URL 不可用 | 安装保持成功，仅输出手动授权路径 |
| 重复执行同版本脚本 | 安全覆盖同版本，不修改 VM 数据 |
| 未来版本发布 | 生成新的版本固定脚本，不修改旧 Release 资产 |

## 6. 涉及文件

- `scripts/install-my-omarchy.sh`：公开一键安装脚本。
- `tests/test-install-my-omarchy.py`：脚本静态契约和隔离安装事务测试。
- `README.md`：一键安装入口、行为与安全边界。
- `docs/releasing.md`：发布时固化版本/摘要、上传和远端复验步骤。
- GitHub Release `v0.5.0`：新增脚本资产并更新说明，不替换现有 DMG/zip。

## 7. 验收标准

1. README 和 v0.5.0 Release 页面都提供同一条版本固定安装命令。
2. 公开 URL 下载的脚本与仓库中的脚本 SHA-256 一致。
3. 正确 DMG 在隔离安装根中完成下载、摘要校验、身份校验、复制、quarantine 清理和启动步骤模拟。
4. 错误摘要、错误 Bundle ID、错误版本、非 arm64、损坏签名分别在覆盖现有 App 前失败。
5. 模拟 VM 运行时脚本在下载和安装前失败，且不发送终止信号。
6. 模拟已有 App 的成功升级保留应用支持目录；模拟复制或最终验证失败会恢复旧 App。
7. 脚本通过 `bash -n` 和 ShellCheck；测试覆盖包含空格的路径。
8. GitHub Release 中脚本资产状态为 `uploaded`，DMG 和 zip 的既有 ID、size、digest 不发生变化。
9. `main`、v0.5.0 tag 和 Release 的关系保持可追踪；v0.5.0 tag 不移动。
