# 本地安全边界加固设计文档

## 1. 概述

### 1.1 背景

My Omarchy 已对启动诊断日志、存储位置、虚拟机生命周期和双向剪贴板建立基础安全检查，但仍有五处边界需要收紧：启动日志会随 session 和运行时间持续增长；日志目录创建后没有像 Secure Enclave key directory 一样验证真实文件类型、所有者和权限；Force Stop 的确认只存在于当前 Overview 页面；Storage location 仍以少量危险根路径黑名单为核心；剪贴板允许单条 16 MiB 原始 payload。

这些问题分别涉及磁盘耗尽、路径替换、误杀虚拟机、状态目录越界和跨虚拟机边界的内存放大风险。本阶段以最小、可测试的方式修复现有实现，不引入完整结构化诊断体系。

### 1.2 目标

1. 将单个 launch diagnostics 文件限制为 10 MiB。
2. 将受管理的 launch diagnostics 保持在最多 10 个 session、合计最多 50 MiB。
3. 验证日志目录和日志文件的真实类型、所有者及精确权限，拒绝符号链接和不安全占位项。
4. 让所有 UI Force Stop 请求经过统一确认，并保证确认结果只能作用于发起时的 VM session。
5. 仅允许 Home 真子目录或外置卷真子目录作为自定义 Storage location。
6. 将 host 和 guest 剪贴板原始 payload 上限统一为 10 MiB。
7. 保持默认 VM 路径、允许范围内的已有 VM、正常停止和其他 runtime 能力兼容。

## 2. 范围与非目标

### 2.1 范围

- `LaunchDiagnosticsLog` 的目录验证、安全文件创建、单文件限制和历史清理。
- SwiftUI、controller 和 AppKit presenter 之间的 Force Stop 确认职责。
- Swift storage policy、环境覆盖、只读空间估算和 shell persistent-storage runtime 的路径白名单。
- macOS native clipboard bridge 与 guest clipboard agent 的 payload 合同。
- 对应 Swift、Python 和 shell 合同测试，以及必要的中英文文案或用户文档。

### 2.2 非目标

- 不实现结构化 JSON diagnostics、统一 error registry、异步日志框架、诊断 zip 或日志上传。
- 不增加用户可配置的日志或剪贴板阈值。
- 不自动移动、复制或删除白名单外的旧 VM 数据。
- 不改变正常 Stop、Restart、应用退出信号或宿主终止信号的既有语义。
- 不压缩、拆分或部分传输超限剪贴板内容。
- 不引入可由生产环境变量开启的测试绕过。

## 3. 设计原则

1. **失败关闭、运行可用**：不安全的日志路径或无法满足日志配额时禁用当前 session 的持久日志，但不阻止 VM 启动；不安全的 Storage location 则必须阻止启动，不能静默回退。
2. **危险操作绑定对象**：Force Stop 的确认绑定具体 management session，不能复用于后续 session。
3. **边界独立验证**：Swift 和 shell 各自验证 Storage 白名单；host 和 guest 各自验证剪贴板大小。
4. **先验证再修改**：已有日志目录和显式 Storage override 在任何 `chmod`、`mkdir` 或文件创建前先完成不跟随链接的边界检查。
5. **最小实现**：扩展现有类型和 presenter，不建立新的通用安全框架或完整 diagnostics 子系统。

## 4. 核心方案

### 4.1 Launch diagnostics 安全目录

默认目录仍为 `~/Library/Logs/My Omarchy/`。创建或复用目录时遵循：

1. 若路径不存在，以 `0700` 创建。
2. 若路径已存在，先用 `lstat` 验证它不是符号链接且确实是目录；验证失败时不执行 `chmod`。
3. 对安全目录设置 `0700` 后再次 `lstat`。
4. 最终必须满足：真实目录、当前 UID 所有、权限精确为 `0700`。
5. 任一检查失败，`LaunchDiagnosticsLog.create` 返回不可用，VM 正常继续启动。

该顺序避免对符号链接目标意外修改权限，并与 Secure Enclave key directory 的最终属性检查保持一致。

### 4.2 日志文件安全创建

日志文件名继续使用 `launch-<epoch>-<pid>-<uuid-prefix>.log`。创建使用：

```text
open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600)
```

创建后通过 `fstat` 验证：

- 文件类型为 regular file；
- owner 为当前 UID；
- 权限精确为 `0600`。

若同名项已经存在、路径是链接或最终属性不符，关闭 descriptor 并放弃该 session 日志；绝不覆盖已有项。`FileHandle` 从已验证 descriptor 构造，避免检查与重新打开之间的替换窗口。

### 4.3 单文件上限

固定合同：

```text
maximumFileBytes = 10 * 1024 * 1024
```

可解码文本先完成 secret redaction，再计算 UTF-8 实际写入长度；非 UTF-8 data 沿用现有原样写入行为，但同样按最终 bytes 计入上限。日志为固定截断标记预留空间：

```text
[my-omarchy] Launch diagnostics truncated at 10 MiB.
```

当一次写入无法完整放入剩余业务内容预算时，只写入能够容纳的前缀，再写一次完整截断标记。之后的追加直接忽略。文件总长度不得超过 10 MiB。不新增二进制内容解析。

写入和 close 继续由当前 lock 串行化。日志限制不能阻塞 QEMU stderr drain：写入失败或达到上限后立即停止该文件后续写入，不重试、不影响 stderr 向终端和内存 recent-error buffer 的传递。

### 4.4 历史日志清理

受管理日志只包括同时满足以下条件的目录直接子项：

- 文件名严格匹配当前 `launch-*.log` 命名格式；
- `lstat` 为当前 UID 所有的 regular file；
- 不是符号链接。

无关文件、不安全条目和子目录不计入配额，也不删除。清理按文件名中的 epoch 排序，并以修改时间和文件名作为稳定兜底；先删除最旧日志。

为了保证当前日志写满后仍满足最终配额，创建新 session 前将历史日志收敛到：

```text
historicalSessionCount <= 9
historicalBytes <= 40 MiB
```

这为当前 session 预留 1 个文件和完整 10 MiB。当前日志关闭后再次执行最终清理：

```text
managedSessionCount <= 10
managedBytes <= 50 MiB
```

若清理失败，或清理后仍无法满足创建前预留合同，则本次不创建持久日志。VM 启动、stderr drain 和内存错误摘要不受影响。总容量合同只覆盖 My Omarchy 管理的安全 `launch-*.log`，不承诺删除用户放入该目录的其他内容。

### 4.5 Force Stop 统一确认

`OverviewView` 不再直接持有和执行 Force Stop 确认。UI 按钮只发送 `.forceStop`，controller 成为确认与执行的唯一入口。

流程如下：

1. `ManagementCommandPolicy` 仍要求 graceful stop/restart 已超时且 `forceStopAvailable` 为真。
2. controller 收到 `.forceStop` 时捕获 `activeManagementSession`，并拒绝重复的 pending confirmation。
3. presenter 显示现有中英文 warning，Cancel 为默认安全动作，Force Stop 为 destructive 动作。
4. 用户确认后，controller 再次验证：
   - captured session 非空且仍等于 `activeManagementSession`；
   - child 仍在运行；
   - `ManagementCommandPolicy` 仍允许 `.forceStop`；
   - 没有应用终止流程接管生命周期。
5. 只有全部成立才向 supervisor 发送 `SIGKILL`。取消、session 改变、VM 已退出或状态恢复均不发送信号。

确认 UI 采用现有 presenter 的 AppKit alert，但 controller 必须持有 pending 状态并在结果返回后复核。AppKit 模态循环会继续处理 main-queue lifecycle 回调，因此不能仅依赖弹窗打开前的状态。为了可确定地测试确认期间的 lifecycle 变化，controller 只增加一个可注入的 Force Stop 确认闭包；生产默认闭包调用 presenter，测试传入同步的确认结果或在闭包内触发 session 变化。不为这一处 seam 引入新的 presenter 协议或通用 UI 抽象。

应用退出、Unix signal 和内部故障处理不属于用户主动点击 Force Stop，不增加这一确认。

### 4.6 Storage location 白名单

自定义 Storage location 只允许以下 canonical path：

1. 当前 macOS 用户 Home 的真子目录：`<home>/<至少一个子组件>`；
2. 外置或已挂载卷的真子目录：`/Volumes/<卷名>/<至少一个子组件>`。

明确拒绝：

- Home 本身；
- `/Volumes`；
- `/Volumes/<卷名>` 卷根；
- `/`、`/Users`、`/private`、`/tmp`、`/opt` 等其他位置；
- 标准化或解析符号链接后落在允许根之外的路径；
- 含 NUL、换行、回车或无法规范化的路径。

路径判断使用组件级祖先关系，不使用字符串前缀。因此 `/Users/alice-copy/...` 不能冒充 `/Users/alice/...`。

#### Swift 边界

`StorageLocationPolicy` 提供可单测的白名单判断，并由以下入口共同使用：

- Finder picker 选择；
- 已保存的 `StorageLocationPreference`；
- `StorageLocationLaunchConfiguration` 的环境覆盖；
- `QEMUGPUStorageSpaceEstimate` 等只读位置解析。

白名单通过后继续执行已有检查：目标存在、最终路径非 symlink、目录类型、当前用户所有、workspace marker、非卷根、空目录规则、本地 APFS 能力和剩余空间。环境覆盖不得绕过完整验证；无效覆盖产生明确 unavailable reason，并阻止启动。

Swift 纯策略测试允许显式注入 test home 和 volume root 参数，但生产调用只使用系统提供的当前用户 Home 与固定 `/Volumes`，不读取可由子进程环境伪造的 allowlist 根。

#### Shell 边界

`qemu-persistent-storage.sh` 在任何 state-root `mkdir` 或 `chmod` 前执行同义白名单检查：

- 默认路径仍是当前用户真实 Home 下的 `Library/Application Support/My Omarchy/VM/v1`，允许按现有流程创建；
- 显式 `OMARCHY_QEMU_GPU_STATE_ROOT` 必须已存在，解析为 physical path 后位于真实 Home 真子目录或 `/Volumes/<卷名>` 真子目录；
- 当前用户真实 Home 从 macOS 账户数据库取得，不以继承的 `$HOME` 作为安全根；
- 白名单外 override 在发生任何文件系统修改前失败。

shell 测试通过测试进程自身的隔离账户根或函数级夹具验证策略，不增加生产环境变量 bypass。Swift 与 shell 都保留代表性合同测试，固定允许与拒绝矩阵。

### 4.7 Storage 兼容和存量影响

- 默认 Application Support VM 路径继续可用。
- Home 真子目录和 `/Volumes/<卷名>` 真子目录中的已有合法 VM 继续可用。
- 白名单外的已保存位置或环境覆盖会变为不可用。应用显示原因，并允许用户沿用现有交互切回默认位置。
- 切回默认位置只修改偏好，不删除、移动或重写旧位置的数据。
- 不允许静默 fallback，因为它可能让用户误以为正在操作原 VM。
- 显式 override 从“可指向任意非黑名单绝对路径”收紧为白名单，属于有意的安全兼容变化。

### 4.8 剪贴板 payload 合同

host 与 guest 固定使用：

```text
maximumPayloadBytes = 10 * 1024 * 1024 = 10_485_760 bytes
maximumLineBytes = maximumPayloadBytes * 4 / 3 + 4096
```

限制针对 base64 前的原始 payload。恰好 10 MiB 接受，10 MiB 加 1 byte 拒绝。超限内容不截断、不部分同步：host pasteboard 读取返回无可发送消息；guest selection 跳过并记录无内容的安全提示；跨 virtio 收到的超限消息保持现有 ignored/error 语义。

## 5. 模块边界与涉及文件

### 5.1 生产代码

- `macos/Sources/MyOmarchy/QEMUGPULauncher.swift`
  - `LaunchDiagnosticsLog` 权限、创建、配额与轮转；
  - supervisor 保持 best-effort 日志语义。
- `macos/Sources/MyOmarchy/OverviewView.swift`
  - 移除页面级 Force Stop 确认状态。
- `macos/Sources/MyOmarchy/ManagementAppKitPresenter.swift`
  - 提供 destructive Force Stop 确认展示。
- `macos/Sources/MyOmarchy/VMApplicationController.swift`
  - 绑定 session 的 Force Stop 确认；
  - Storage override 完整验证。
- `macos/Sources/MyOmarchy/StorageLocation.swift`
  - 白名单策略和所有 Swift 入口收敛。
- `macos/qemu-persistent-storage.sh`
  - runtime 白名单和可信 Home 解析。
- `macos/Sources/MyOmarchy/NativeClipboardBridge.swift`
- `guest/native-overlay/usr/local/bin/omarchy-native-clipboard-bridge`
  - 10 MiB 双端合同。
- `macos/Sources/MyOmarchy/Resources/*/Localizable.strings`
  - 仅在现有文案不能复用时调整确认文案。

### 5.2 测试

- `macos/Tests/MyOmarchyTests/QEMUGPULauncherTests.swift`
- `macos/Tests/MyOmarchyTests/ManagementControllerBridgeTests.swift`
- `macos/Tests/MyOmarchyTests/StorageLocationTests.swift`
- `macos/Tests/MyOmarchyTests/NativeClipboardBridgeTests.swift`
- `macos/Tests/qemu-persistent-storage.test.sh`
- `guest/tests/test_native_clipboard_bridge.py`

不要求为了本阶段新建通用 logging、filesystem policy 或 lifecycle framework。只有当现有文件无法保持单一职责时，才允许提取小型内部 helper。

## 6. TDD 实施步骤

1. 为日志安全目录、排他文件创建、10 MiB 上限、截断标记、9/40 创建前预留和 10/50 最终清理写失败测试。
2. 以最小修改实现 `LaunchDiagnosticsLog` 加固，使 focused tests 通过。
3. 为 Force Stop 确认、取消、重复触发、确认中退出和 session 切换写失败测试。
4. 将确认下沉到 controller/presenter，并移除 Overview 的独立确认逻辑。
5. 为 Swift Storage allowlist 写允许/拒绝矩阵及环境覆盖、空间估算回归测试。
6. 实现 Swift 白名单并让所有入口统一使用。
7. 为 shell runtime 写同义 allowlist 合同测试，调整 `/private/tmp` 测试夹具而不加入生产 bypass。
8. 实现 shell 白名单和可信 Home 获取。
9. 为 host/guest 写 10 MiB 和 10 MiB + 1 byte 边界测试，再调整双方常量。
10. 运行 focused tests、完整 `make test`，并检查最终 diff、用户文档和设计合同一致性。

## 7. 测试规划

| 类型 | 覆盖点 | 关键用例 |
|---|---|---|
| Swift 单元 | 日志目录 | 新目录、已有安全目录、symlink、非目录、owner/mode 不符 |
| Swift 单元 | 日志文件 | `O_EXCL` 碰撞、链接占位、`0600`、当前 UID、写入失败 |
| Swift 单元 | 日志容量 | 恰好上限、跨上限、完整截断标记、后续无增长 |
| Swift 单元 | 历史清理 | 超过 9/40、超过 10/50、最旧优先、无关文件保留、不安全项保留 |
| Swift 单元 | Force Stop | 取消、确认、重复请求、VM 退出、session 切换、策略恢复为禁止 |
| Swift 单元 | Storage | Home 子目录、Home 根、相似前缀、卷子目录、卷根、其他绝对路径、symlink 逃逸 |
| Swift 集成 | Storage 入口 | 保存偏好、环境覆盖、只读估算、启动配置一致 |
| Shell 合同 | Storage runtime | 默认路径、Home 子目录、卷子目录、`/tmp`、`/private`、卷根、缺失 override |
| Swift/Python | Clipboard | 10 MiB 接受、10 MiB + 1 拒绝、line budget 同步 |
| 回归 | 全仓库 | `make test` |

测试必须先证明原行为会失败，再用最小实现转绿。不得通过放宽断言、跳过检查或增加可在生产启用的 test-only 环境变量获得绿灯。

## 8. 风险与控制

| 风险 | 控制 |
|---|---|
| 当前日志增长后突破总配额 | 创建前使用 9/40 预留，关闭后使用 10/50 收敛 |
| 日志路径被链接替换 | 目录 `lstat` 前置；文件 `O_NOFOLLOW | O_EXCL` 加 `fstat` |
| 清理误删用户文件 | 只删除严格命名且安全属性匹配的受管理日志 |
| 确认后误杀新 session | 捕获并复核 management session 与当前状态 |
| 环境覆盖绕过 UI 白名单 | Swift launch configuration 与 shell runtime 双重拒绝 |
| `$HOME` 被伪造 | shell 使用账户数据库中的真实 Home |
| 测试依赖 `/private/tmp` | 注入纯策略参数或调整可信测试根，不增加生产 bypass |
| 白名单导致旧路径不可用 | 明确提示、允许切回默认、不迁移或删除旧数据 |
| host/guest 剪贴板合同漂移 | 两端边界测试和从同一数值推导 line budget |

## 9. 验收标准

1. 每个 launch log 最多 10 MiB，超限时最多出现一次完整截断标记。
2. 正常单实例生命周期中，受管理日志在当前文件写满后仍不超过 10 个和 50 MiB。
3. 不安全日志目录、symlink 文件路径和同名碰撞不会被跟随、覆盖或修改目标权限。
4. 日志安全或容量检查失败不会阻止 VM 启动，但当前 session 不产生持久日志。
5. 所有 UI Force Stop 都出现确认；取消、VM 退出、session 改变或策略失效均不发送 `SIGKILL`。
6. Home 真子目录与 `/Volumes/<卷名>` 真子目录可作为自定义 Storage location。
7. Home、`/Volumes`、卷根和其他所有路径在 Swift、环境覆盖与 shell runtime 中均被拒绝。
8. Storage 拒绝发生在任何目标目录创建、chmod 或 marker 写入之前。
9. 白名单外旧位置不被移动、修改或删除，应用不静默切换到默认 VM。
10. host 与 guest 都接受恰好 10 MiB clipboard payload，并拒绝 10 MiB + 1 byte。
11. 所有 focused tests 和仓库完整门禁 `make test` 通过。

## 10. 回滚策略

- 日志加固可独立回滚到原 best-effort writer；回滚不会改变 VM 数据。
- Force Stop 变更只影响确认路径，可在不修改 lifecycle state model 的情况下回滚。
- Storage 白名单回滚只恢复旧路径接受范围，不需要迁移数据；本阶段从不移动数据。
- Clipboard 上限回滚必须同时恢复 host 和 guest，禁止单边回滚造成协议漂移。

本阶段不创建新的持久 schema，因此不需要数据迁移或降级转换。
