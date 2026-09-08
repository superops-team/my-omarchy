# My Omarchy 诊断与故障恢复设计文档

## 1. 概述

### 1.1 问题

当前 launcher 只在内存中保留有限 stderr 尾部，除少数端口和存储错误外，大多数启动失败最终提示“重新安装”。用户无法复制完整诊断、打开日志、区分磁盘满、权限、签名、boot kit、HVF/GPU 或 guest 启动故障，也缺少经过约束的安全恢复入口。

### 1.2 目标

1. 建立隐私安全、容量有界、可导出的诊断记录。
2. 将高频故障映射为明确原因和可执行动作。
3. 为存储、权限、端口、VM 暂停和升级故障提供非破坏性恢复路径。
4. 通过故障注入验证提示与行为，而不是依赖人工猜测。

## 2. 用户场景

### 场景 1：启动失败自助定位

**Given** VM 因宿主磁盘空间不足而无法启动

**When** launcher 收到失败

**Then** UI 显示“宿主磁盘空间不足”、所需/可用空间，并提供打开 VM 位置和复制诊断，不建议重装

### 场景 2：提交 Issue

**Given** 用户遇到未知故障

**When** 用户点击“导出诊断”

**Then** 得到已脱敏、带版本和错误分类的压缩包，可安全附加到 `superops-team/my-omarchy/issues`

### 场景 3：安全恢复

**Given** VM 在 Mac 唤醒后仍暂停

**When** 用户选择重试恢复

**Then** App 只执行对应 QMP 恢复流程，不自动 Reset 或删除数据

## 3. 功能需求

### FR-1：结构化错误模型

所有用户可见失败映射到稳定 error code，至少覆盖：

- app 签名/资源完整性；
- HVF、CPU、VirGL/ANGLE/Cocoa runtime；
- 宿主空间、guest 空间、workspace 权限、外置卷断开；
- persistent metadata、boot kit、upgrade candidate、backup；
- QMP、guest boot timeout、unexpected QEMU exit；
- TCC 权限、音频、摄像头、剪贴板 bridge；
- port forwarding bind 冲突；
- unknown。

错误对象包含 code、stage、用户标题、影响、建议动作、可重试性、是否可能涉及数据风险和关联日志 session ID。

### FR-2：持久日志

为 launcher、QEMU、QMP、audio/camera/clipboard bridge、storage/lifecycle 建立统一 session 日志。日志写入 `~/Library/Logs/My Omarchy/`，单文件和总容量均有限制，默认保留最近 10 次 session 或 50 MiB，以先到者为准。写入必须异步且不能阻塞 QEMU stderr drain。

### FR-3：隐私脱敏

日志默认不记录剪贴板内容、摄像头帧、麦克风数据、凭据、环境变量值或共享文件内容。导出时将用户名、HOME、共享目录和外置卷路径替换为稳定占位符；端口、版本、hash 和 error code 保留。原始日志目录权限为 0700，文件为 0600。

### FR-4：诊断包

“复制诊断摘要”输出短文本；“导出诊断”生成 zip，包含最近相关 session、system profile 白名单、App/guest/runtime identity、签名验证、存储 metadata 摘要、磁盘空间和 checksum。导出前显示内容预览，不包含 root disk 或用户文件。

### FR-5：错误页动作

根据 error code 提供有限动作：重试、打开日志、复制诊断、导出诊断、打开 VM 目录、打开系统权限设置、释放候选升级空间、回滚、退出。Factory Reset 永远不是默认按钮，且必须保持独立的输入确认。

### FR-6：启动与健康超时

启动阶段定义可观测状态：preflight、storage prepare、QEMU spawned、QMP ready、guest boot、graphical ready。每阶段有独立 timeout 和错误码；正常慢启动不能被统一误判为 QEMU 崩溃。graphical ready 信号必须来自受约束的 guest service，并绑定启动 session。

### FR-7：故障注入

测试可以确定性注入空间不足、损坏 metadata、缺失 boot kit、HVF 不可用、QMP timeout、端口占用、bridge 退出、外置盘断开、upgrade health 失败和日志写入失败。每种故障验证错误码、用户提示、动作集合和数据不变性。

### FR-8：支持入口

所有诊断 UI 与文档只链接 `https://github.com/superops-team/my-omarchy/issues` 和项目安全报告入口。不得链接 Try Omarchy。

## 4. 实现方案

### 4.1 模块边界

- `DiagnosticSession`：session ID、阶段和结构化事件。
- `RotatingLogStore`：权限、轮转和异步写入。
- `FailureClassifier`：从 exit status、QMP、stderr marker 和 storage result 生成 error code。
- `DiagnosticExporter`：白名单采集、脱敏、预览和 zip。
- `RecoveryActionPolicy`：error code 到允许动作的唯一映射。

模块不能直接互相执行破坏性动作；恢复动作仍由 lifecycle/storage controller 校验。

### 4.2 日志格式

使用一行一个 JSON event，字段包括 timestamp、session、component、stage、severity、code、message 和经过白名单处理的 metadata。人类可读 UI 从结构化事件生成，不把原始 shell 错误直接展示给用户。

### 4.3 未知错误

未知错误显示 session ID、退出阶段和安全的通用动作，不再默认建议重装。只有 bundle 签名或资源完整性失败时才建议从官方 My Omarchy Release 重新安装。

## 5. 边界情况

| 场景 | 处理方式 |
|------|----------|
| 日志目录不可写 | 继续尝试安全关机，UI 显示诊断降级 |
| stderr 高频输出 | 有界 drain 到文件，UI 仅保留摘要，不无限增长内存 |
| 用户拒绝导出 | 不创建临时 zip |
| 路径含非 ASCII | 脱敏器按 URL/path 组件处理，不破坏 JSON |
| 同时发生多个错误 | 保留完整事件链，用户页展示主因和次要影响 |
| App 崩溃 | 下次启动发现未正常结束 session 并提供诊断，不自动修改 VM |

## 6. 涉及文件

- `macos/Sources/OmarchyVMHelper/QEMUGPULauncher.swift`
- `VMApplicationController`、QMP、bridge 和 storage 模块
- 启动菜单与错误对话框
- shell launcher 的稳定 marker/error code 输出
- guest graphical health service
- 故障注入测试和支持文档

## 7. 验收标准

1. launcher/QEMU/bridge 日志可跨 App 退出保留，轮转后不超过配置上限。
2. 日志与诊断包中没有剪贴板内容、媒体数据、凭据、HOME 原值或共享目录原值。
3. 至少十类故障具有稳定 error code、准确标题和对应安全动作。
4. 磁盘满、端口冲突、权限拒绝、boot kit 损坏不得统一提示重装。
5. 导出包包含 App、guest、runtime、macOS、机型、阶段和 session ID，可用于复现。
6. 每项故障注入都验证 active VM disk hash 或 metadata 未被意外修改。
7. Factory Reset 始终保持独立确认，不因诊断流程降低保护。
8. 所有支持链接指向 `superops-team/my-omarchy`。
