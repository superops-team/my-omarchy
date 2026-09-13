# 本地安全边界加固功能验证 Case

## 1. 执行约定

- 仓库根目录：`/Users/bytedance/workspace/github/my-omarchy`
- 证据目录：`.build/verification/local-security-hardening/`
- 每条自动化命令使用 `tee` 保存完整输出；报告记录命令、环境、状态和证据路径。
- 测试只能操作测试创建的临时目录；不得修改 `~/Library/Application Support/My Omarchy`、真实外置卷或用户现有 VM。
- 所有 P0/P1 Case 必须通过后才能进入代码评审。

## 2. Case 清单

### VC-LOG-001：日志目录和文件拒绝链接替换

- 优先级：P0
- 覆盖：目录权限验证、安全文件创建、无副作用失败
- 前置环境：macOS；Swift test 可创建隔离临时目录和 symlink。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter QEMUStandardErrorDrainTests
  ```

- 输入：安全目录、`0755` 当前用户目录、指向其他目录的 symlink、普通文件占位目录、与目标日志同名的 regular file 和 symlink。
- 预期结果：安全目录最终为 `0700`，日志为当前 UID 所有的 regular `0600` 文件；symlink/非目录被拒绝且目标权限和内容不变；同名项不被覆盖。
- 通过标准：focused suite 通过，负向用例明确断言目标未被修改。
- 证据：`.build/verification/local-security-hardening/VC-LOG-001.log`
- 失败处理：回到日志目录或原子创建实现，禁止放宽属性断言。

### VC-LOG-002：单文件 10 MiB 硬上限

- 优先级：P0
- 覆盖：长时间运行磁盘保护、截断行为、secret redaction 顺序
- 前置环境：同 VC-LOG-001。
- 执行命令：同 VC-LOG-001。
- 输入：连续追加跨越 10 MiB 的文本和 data，随后继续追加；包含被任意 stderr callback 分块拆开的可识别 secret。
- 预期结果：文件大小不超过 `10 * 1024 * 1024`；截断标记完整且只出现一次；后续追加不增长；写入文件的可解码文本仍不含 secret 明文。
- 通过标准：focused suite 通过并断言精确 byte 上限。
- 证据：`.build/verification/local-security-hardening/VC-LOG-002.log`
- 失败处理：回到写入预算计算；不得删掉截断或脱敏断言。

### VC-LOG-003：历史日志 9/40 预留与 10/50 最终配额

- 优先级：P0
- 覆盖：session 数量、总容量、最旧优先清理、无关文件保护
- 前置环境：隔离临时日志目录。
- 执行命令：同 VC-LOG-001。
- 输入：不同 epoch 的受管理日志、无关文件、symlink 和不安全所有权/权限夹具；历史总量分别越过 40 MiB 和 50 MiB；打开日志目录后替换同名路径；当前 session 写入后令总量超过最终配额。
- 预期结果：创建前最多 9 个/40 MiB；当前日志关闭后最多 10 个/50 MiB；只删除已打开目录中的最旧安全受管理日志；同名替代目录、无关或不安全条目保持不变；无法满足预留时不创建新日志。
- 通过标准：focused suite 全部通过。
- 证据：`.build/verification/local-security-hardening/VC-LOG-003.log`
- 失败处理：回到受管理文件识别或清理顺序，禁止扩大删除范围。

### VC-FORCE-001：Force Stop 确认、取消和去重

- 优先级：P0
- 覆盖：危险操作确认统一入口
- 前置环境：注入 recording supervisor 和确认闭包。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter ManagementControllerBridgeTests
  ```

- 输入：graceful stop timeout 后依次模拟取消、确认和确认未完成时的重复点击。
- 预期结果：取消不发送信号；确认只发送一次 `SIGKILL`；重复点击只出现一个 pending confirmation。
- 通过标准：recording supervisor 的信号序列精确匹配预期。
- 证据：`.build/verification/local-security-hardening/VC-FORCE-001.log`
- 失败处理：回到 controller pending 状态和唯一入口，不在 View 增加旁路。

### VC-FORCE-002：确认绑定 management session

- 优先级：P0
- 覆盖：模态事件循环竞态、误杀保护
- 前置环境：同 VC-FORCE-001。
- 执行命令：同 VC-FORCE-001。
- 输入：确认闭包返回前模拟原 VM 退出、active session 改变、force-stop policy 失效或应用终止流程接管。
- 预期结果：所有状态漂移场景均不发送 `SIGKILL`。
- 通过标准：每个场景的信号序列为空，当前 lifecycle 不被确认结果篡改。
- 证据：`.build/verification/local-security-hardening/VC-FORCE-002.log`
- 失败处理：回到确认后复核逻辑，禁止只校验 PID 或弹窗前状态。

### VC-STORAGE-001：Swift Storage 白名单允许矩阵

- 优先级：P0
- 覆盖：Home 和外置卷合法子目录
- 前置环境：可注入 test Home、`/Volumes` 根、volume probe 与 root detector。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter StorageLocationPolicyTests
  ```

- 输入：Home 下一级/多级目录、`/Volumes/TestDisk/VMs`、已有合法 workspace marker。
- 预期结果：白名单判断通过，并继续执行 owner、marker、APFS、local-volume 和空间检查。
- 通过标准：允许矩阵全部通过且既有 Storage tests 不回归。
- 证据：`.build/verification/local-security-hardening/VC-STORAGE-001.log`
- 失败处理：修复组件级祖先判断，不扩大允许根。

### VC-STORAGE-002：Swift Storage 白名单拒绝与无 fallback

- 优先级：P0
- 覆盖：根路径、前缀伪造、symlink 逃逸、环境覆盖和只读入口
- 前置环境：同 VC-STORAGE-001。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter StorageLocationTests
  ```

- 输入：Home、`/Volumes`、卷根、`/tmp`、`/private`、`/opt`、Home 相似前缀、指向白名单外的 symlink、非法 `OMARCHY_QEMU_GPU_STATE_ROOT`。
- 预期结果：全部拒绝；launch configuration 返回 unavailable reason；空间估算不解析该位置；不静默使用默认 VM。
- 通过标准：focused suite 通过，并检查环境字典未携带非法 root。
- 证据：`.build/verification/local-security-hardening/VC-STORAGE-002.log`
- 失败处理：回到统一 policy 接入点，禁止仅修 UI picker。

### VC-STORAGE-003：shell runtime 白名单和修改前拒绝

- 优先级：P0
- 覆盖：runtime 防绕过、可信 Home、无副作用失败
- 前置环境：测试使用隔离 Home/Volumes 夹具，不触碰真实 VM。
- 执行命令：

  ```bash
  macos/Tests/qemu-persistent-storage.test.sh
  ```

- 输入：默认路径、Home 子目录、卷子目录、Home 根、卷根、`/private/tmp`、不存在的显式 override、伪造 `$HOME`。
- 预期结果：允许项通过；拒绝项在 `mkdir`、`chmod` 和 marker 写入前失败；账户数据库 Home 不被伪造 `$HOME` 替换。
- 通过标准：shell suite 通过，拒绝目标不存在或 metadata 完全未改变。
- 证据：`.build/verification/local-security-hardening/VC-STORAGE-003.log`
- 失败处理：回到 shell preflight；禁止新增生产 test bypass。

### VC-STORAGE-004：白名单外旧偏好保留数据

- 优先级：P1
- 覆盖：存量兼容和回滚路径
- 前置环境：隔离 UserDefaults 与临时旧 workspace。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter StorageLocationTests
  ```

- 输入：保存一个白名单外但内容有效的旧 workspace preference。
- 预期结果：启动被阻止并返回明确原因；旧目录、marker 和内容不变；切换默认只改变 preference。
- 通过标准：内容 hash/存在性保持且没有 silent fallback。
- 证据：`.build/verification/local-security-hardening/VC-STORAGE-004.log`
- 失败处理：修复迁移/提示逻辑，不自动搬迁。

### VC-CLIP-001：macOS clipboard 10 MiB 边界

- 优先级：P1
- 覆盖：host 消息构造与解码边界
- 前置环境：Swift test。
- 执行命令：

  ```bash
  cd macos
  swift test --disable-sandbox --filter NativeClipboardBridgeTests
  ```

- 输入：`10_485_760` bytes 和 `10_485_761` bytes。
- 预期结果：前者可构造并往返；后者构造或 decode 被拒绝；line budget 从 payload 常量推导。
- 通过标准：focused suite 通过。
- 证据：`.build/verification/local-security-hardening/VC-CLIP-001.log`
- 失败处理：修复 host 常量或边界比较。

### VC-CLIP-002：guest clipboard 10 MiB 边界

- 优先级：P1
- 覆盖：guest send/decode/read 上限
- 前置环境：Python 3。
- 执行命令：

  ```bash
  python3 -m unittest guest.tests.test_native_clipboard_bridge
  ```

- 输入：`10_485_760` bytes 和 `10_485_761` bytes。
- 预期结果：前者接受，后者在完整载入或发送前被拒绝；`MAX_LINE_BYTES` 与 host 公式一致。
- 通过标准：guest suite 通过。
- 证据：`.build/verification/local-security-hardening/VC-CLIP-002.log`
- 失败处理：修复 guest 常量和 bounded read，不改变格式协议。

### VC-REG-001：完整仓库回归

- 优先级：P0
- 覆盖：所有变更及关键既有能力
- 前置环境：仓库工具链满足 `make test`。
- 执行命令：

  ```bash
  make test
  ```

- 输入：仓库完整 Swift、Python、guest 和 shell suites。
- 预期结果：全部退出 0，无跳过安全检查或弱化断言。
- 通过标准：命令退出 0。
- 证据：`.build/verification/local-security-hardening/VC-REG-001.log`
- 失败处理：回到受影响 Task 修复并重新执行相关 Case 及全量回归。

### VC-E2E-001：本机 App 构建和启动安全路径

- 优先级：P1
- 覆盖：真实产物、AppKit 接线、默认 Storage 和 diagnostics 创建
- 前置环境：Apple Silicon macOS；现有 guest/runtime artifacts 可用。
- 执行步骤：

  ```bash
  make app
  open "dist/app.noindex/My Omarchy.app"
  ```

  打开管理窗口，确认默认 Storage 可用；触发一次不会破坏数据的启动预检；检查最新 launch log 权限与大小；在不满足 Force Stop 展示条件时确认没有直接 Force Stop 入口。测试后正常退出 App。
- 预期结果：App 正常启动；默认路径未被白名单拒绝；日志目录 `0700`、文件 `0600` 且不超过 10 MiB；无异常崩溃。
- 通过标准：构建退出 0，操作记录与权限命令输出符合预期。
- 证据：`.build/verification/local-security-hardening/VC-E2E-001.log` 和必要截图。
- 失败处理：回到对应 Task；不得用测试二进制替代 App 产物结论。

## 3. 覆盖矩阵

| Spec 验收项 | Case |
|---|---|
| 日志单文件 10 MiB、一次截断标记 | VC-LOG-002 |
| 受管理日志最多 10 个/50 MiB | VC-LOG-003 |
| 日志目录/文件防 symlink 和覆盖 | VC-LOG-001 |
| 日志失败不阻止 VM | VC-LOG-001、VC-LOG-003、VC-E2E-001 |
| Force Stop 必须确认 | VC-FORCE-001 |
| Force Stop 绑定 session | VC-FORCE-002 |
| Home/Volumes 真子目录允许 | VC-STORAGE-001、VC-STORAGE-003 |
| 其他路径三层拒绝 | VC-STORAGE-002、VC-STORAGE-003 |
| 拒绝发生在修改前 | VC-STORAGE-003 |
| 旧位置不迁移、不删除、不 fallback | VC-STORAGE-004 |
| host/guest 10 MiB clipboard | VC-CLIP-001、VC-CLIP-002 |
| 完整回归与真实 App 接线 | VC-REG-001、VC-E2E-001 |

## 4. 执行顺序与证据

1. 按模块执行 VC-LOG、VC-FORCE、VC-STORAGE、VC-CLIP focused Case。
2. 修复任何失败后重新执行该模块全部 Case。
3. 执行 VC-REG-001。
4. 两轮代码评审通过后执行 VC-E2E-001。
5. 将命令、退出码、关键输出和证据路径汇总到 `verification-report.md`。

证据日志包含本地绝对路径时只保存在 `.build/`；提交的报告使用仓库相对路径和脱敏摘要。
