# 自定义虚拟机资源档设计文档

## 1. 概述

### 1.1 背景

My Omarchy 当前仅提供“自动”和“低资源”两个资源档。自动档根据宿主内存和逻辑 CPU 数选择固定组合，低资源档固定为 4 vCPU 与 2048 MiB。两个档位可以覆盖默认启动和故障恢复，但无法满足编译、浏览器多任务、内存密集服务等差异化业务负载。

### 1.2 目标

1. 保留现有自动档和低资源档。
2. 新增自定义档，允许用户独立设置虚拟机 CPU 核数和内存。
3. CPU 始终至少为 macOS 保留 4 个逻辑核心。
4. 内存最多使用宿主物理内存的 70%。
5. 自定义值仅在下次 VM 启动时生效，运行中只读。
6. 离开自定义档后保留历史自定义值，重新选择时恢复。
7. Swift 与 shell 各自验证同一安全合同，非法值绝不传给 QEMU。

## 2. 用户场景

### 场景 1：选择自定义档

**Given** VM 已停止，宿主满足最低资源要求

**When** 用户在“虚拟机 → 资源”选择“自定义”

**Then** 页面内联展开 CPU 和内存控件，并显示最终启动配置和宿主保留资源。

### 场景 2：按业务负载调整资源

**Given** 用户选择自定义档

**When** 用户调整 CPU 或内存

**Then** 值被即时持久化，但仅在下次启动时生成 QEMU `-smp` 与 `-m` 参数。

### 场景 3：保留历史配置

**Given** 用户曾保存自定义 CPU 和内存

**When** 用户切换到自动或低资源，再切回自定义

**Then** 上次自定义值保持不变并重新显示。

### 场景 4：更换到资源更小的 Mac

**Given** 已保存的自定义值超过当前宿主安全上限

**When** 用户打开管理界面或尝试启动

**Then** 页面保留原值、显示越界原因并禁止启动；系统不静默改写历史配置。

## 3. 功能需求

### FR-1：三种资源档

资源偏好包含：

- 自动：保持现有宿主自适应规则；
- 低资源：保持 4 vCPU / 2048 MiB；
- 自定义：使用用户保存的 CPU 与内存。

### FR-2：CPU 范围

- 最小 4 vCPU；
- 最大为宿主逻辑 CPU 数减 4；
- 步进 1 vCPU；
- 宿主少于 8 个逻辑 CPU 时，自定义档不可用。

不设置额外固定上限。例如 20 个逻辑 CPU 的宿主可配置到 16 vCPU。

### FR-3：内存范围

- 最小 2048 MiB；
- 最大为宿主物理内存 MiB 的 70%，向下取整到 512 MiB；
- 步进 512 MiB；
- 上限不得低于最低值。

36 GiB 宿主的自定义上限为 25 GiB，即 25600 MiB。

### FR-4：生效时机

- VM 已停止时可修改档位和自定义值；
- launching、running、stopping、restarting 时控件只读；
- 页面明确显示“下次启动生效”；
- 当前运行配置与下次启动配置不得混淆。

### FR-5：持久化与迁移

资源偏好 schema 升级并原子保存：

- 当前档位；
- 上次自定义 vCPU；
- 上次自定义内存 MiB。

旧 schema 的 automatic / lowResource 配置无损迁移。损坏、未来 schema 或字段类型错误时回退到自动档和安全的默认自定义值。合法但超过当前宿主上限的历史值不改写，仅标记为不可启动。

### FR-6：安全失败

- 自定义值低于 4 vCPU 或 2048 MiB时拒绝；
- CPU 未为 macOS 保留 4 个逻辑核心时拒绝；
- 内存超过宿主物理内存 70% 时拒绝；
- 内存不是 512 MiB 的整数步进时拒绝；
- 所有校验失败均生成明确错误，不发布部分环境变量。

## 4. 实现方案

### 4.1 领域模型

将 `VMResourceProfilePreference` 从简单枚举扩展为包含档位和历史自定义值的值对象。`VMResourceProfile` 新增宿主资源限制计算和 `custom(...)` 构造器。

统一约束：

```text
customCPU.min = 4
customCPU.max = hostLogicalCPUCount - 4
customMemory.min = 2048 MiB
customMemory.max = floor(hostMemoryMiB * 0.70 / 512) * 512 MiB
```

### 4.2 持久化

偏好 store schema 升级到 v2。读取 v1 时按原档位迁移，并给自定义历史值设置不超过当前旧默认能力的安全初始值：4 vCPU / 4096 MiB。迁移只发生在内存中；除非用户修改，不主动重写 UserDefaults。

### 4.3 管理界面

资源档 Picker 增加“自定义”。选择后在同一 Form Section 内展开：

- CPU Stepper，显示“X 核”；
- 内存 Stepper，显示 GiB 或 0.5 GiB；
- 实际启动配置摘要；
- “为 macOS 保留至少 4 核和约 X GiB 内存”的说明；
- 越界时显示内联错误并禁止启动。

自定义控件使用原生 Stepper/Picker 语义，保留键盘与 VoiceOver 支持。

### 4.4 控制器与启动合同

SwiftUI 仅发送更新偏好的语义命令。`VMApplicationController` 继续作为唯一写入者和启动事实源。`VMResourceLaunchConfiguration` 校验后发布：

- `OMARCHY_QEMU_GPU_RESOURCE_PROFILE=custom-v1`；
- `OMARCHY_QEMU_GPU_VCPUS=<value>`；
- `OMARCHY_QEMU_GPU_MEMORY_MIB=<value>`。

shell 读取宿主 `sysctl` 数据并重复校验最小值、CPU 保留量、70% 内存上限和 512 MiB 步进。

## 5. 边界情况

| 场景 | 处理方式 |
|------|---------|
| 宿主只有 8 个逻辑 CPU | 自定义 CPU 只能为 4 |
| 宿主少于 8 个逻辑 CPU | 自定义档不可用，自动/低资源沿用现有支持判断 |
| 36 GiB 宿主 | 内存上限向下取整为 25 GiB |
| 历史自定义值超过新宿主上限 | 保留并展示，禁止启动直到用户调整 |
| 运行中切换或调整 | 控件禁用，不修改偏好 |
| 偏好损坏 | 回退自动档，不向 QEMU 传递非法值 |
| shell 收到手工伪造环境变量 | 独立拒绝启动 |

## 6. 实施步骤

1. 为宿主自适应 CPU/内存上下限和边界写失败测试。
2. 扩展资源模型，加入自定义构造与校验。
3. 为 schema v1 迁移、v2 往返、损坏值、历史值保留写测试并实现 store。
4. 扩展管理命令、控制器快照和运行中门控。
5. 扩展 shell 资源合同与 shell 测试。
6. 实现三档 Picker 和自定义 CPU/内存内联控件。
7. 补齐英文、简体中文资源。
8. 运行 Swift 全量、shell 合同、`make test` 和本地 App 验证。

## 7. 涉及文件

- `macos/Sources/MyOmarchy/VMResourceProfile.swift`
- `macos/Sources/MyOmarchy/ManagementCommand.swift`
- `macos/Sources/MyOmarchy/ManagementDetails.swift`
- `macos/Sources/MyOmarchy/VMApplicationController.swift`
- `macos/Sources/MyOmarchy/VirtualMachineView.swift`
- `macos/Sources/MyOmarchy/Resources/*/Localizable.strings`
- `macos/run-qemu-gpu.sh`
- 对应 Swift 与 shell 测试

## 8. 验收标准

1. 自动、低资源、自定义三个档位均可选择。
2. CPU 最小 4，最大为宿主逻辑 CPU 减 4，无额外固定上限。
3. 内存最小 2 GiB，最大为宿主物理内存 70%，按 512 MiB 向下取整。
4. 当前 12 核 / 36 GiB Mac 显示 4–8 vCPU、2–25 GiB。
5. 切出自定义档后历史值保持，切回时恢复。
6. VM 运行中控件只读，修改仅下次启动生效。
7. 越界历史值保留但阻止启动，错误说明准确。
8. Swift 与 shell 对所有边界一致，非法参数不能进入 QEMU。
9. 英文与简体中文界面完整。
10. 仓库现有测试和本地 App 构建保持通过。
