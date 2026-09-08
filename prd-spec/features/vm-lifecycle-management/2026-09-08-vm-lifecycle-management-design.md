# My Omarchy VM 生命周期管理设计文档

## 1. 概述

### 1.1 问题

持久 VM 当前可以跨 App 更新保留，但新版 App 不会把 direct-boot kernel、headers、My Omarchy runtime、本地仓库和 compatibility backports 更新到已有 VM。用户只能 Factory Reset 才能获得完整 factory 内容。同时项目没有用户可用、经过验证的整机备份与恢复合同。

My Omarchy 是全新产品，本方案只处理 My Omarchy v1 以后版本之间的生命周期，不支持 Try Omarchy VM。

### 1.2 目标

1. 为 My Omarchy VM 提供版本化、原子、失败可回滚的无损升级。
2. 提供一致、可验证、不覆盖现有数据的 VM 备份与恢复。
3. 在 UI 中明确 App、factory、VM runtime 和升级状态。
4. 保留用户、文件、应用、配置和 SSH host identity。

### 1.3 非目标

- 不导入或升级 Try Omarchy VM。
- 不承诺任意降级到旧 My Omarchy 版本。
- 不把普通 Omarchy/pacman 更新等同于 My Omarchy runtime 升级。
- 不在首版提供运行中内存快照或 live migration。

## 2. 核心版本模型

每个 VM 持久记录：

- `productIdentity = my-omarchy`；
- storage schema；
- boot ABI；
- factory identity；
- installed My Omarchy runtime generation；
- kernel/initramfs identity；
- migration history；
- active/previous generation；
- 最近一次健康检查结果。

App 启动时只接受 My Omarchy identity。任何 Try Omarchy、未知或手工伪造 identity 均视为外部数据，不进入迁移路径。

## 3. 用户场景

### 场景 1：无损升级

**Given** 用户拥有已配置且包含个人文件的旧版 My Omarchy VM

**When** 新 App 检测到唯一有效迁移链并获得用户确认

**Then** 系统在候选 clone 上升级并验证，成功后原子切换，用户数据、应用、配置和 SSH host key 保持不变

### 场景 2：升级中断

**Given** 候选 VM 正在迁移

**When** App 崩溃、Mac 重启或磁盘空间不足

**Then** 原 active generation 不变，下次启动可以安全清理或继续候选流程

### 场景 3：备份恢复

**Given** 用户已关闭 VM 并导出备份

**When** 用户在没有现存 My Omarchy VM 的位置恢复备份

**Then** 系统验证完整性和 ABI 后恢复并启动，用户数据与 SSH identity 保持一致

## 4. 功能需求

### FR-1：升级清单

每个 release 提供签名且被 App provenance 绑定的 update manifest，声明 source generation、target generation、kernel、initramfs、离线包集合、owned payload、迁移脚本、预期磁盘空间和 hash。迁移只允许执行从当前 generation 到目标 generation 的唯一连续链。

### FR-2：事务升级

升级必须在 active disk 的 APFS clone 上执行；若 clone 不可用则允许用户选择有足够空间的 full copy，不得原地修改 active disk。候选盘使用目标 boot kit 进行隔离的离线迁移和健康检查。只有以下条件全部满足才可原子提升：

1. manifest/hash 验证；
2. 所有迁移脚本成功；
3. 离线文件系统检查通过；
4. boot health 成功；
5. 图形会话 health 成功；
6. QEMU 干净退出；
7. host journal 完整提交。

### FR-3：回滚窗口

前一代 VM 至少保留到新代完成一次图形启动并被用户使用后正常关机。若新代无法启动，UI 提供回滚。完成验证后再提示用户回收旧代空间，不自动静默删除。

### FR-4：迁移脚本安全边界

迁移脚本由 release 签名输入生成，使用受限环境、固定工具路径、无网络、最小挂载权限执行。每个 migration ID 只能成功记录一次，必须具备 verify/apply 语义和幂等重试能力。用户控制的 guest 状态只能提供 health 信号，不能决定 host 激活路径。

### FR-5：版本展示

启动菜单显示 App version、bundled factory、active VM runtime、kernel 和状态：最新、可升级、升级中、回滚可用、不兼容。不得只显示 App 版本。

### FR-6：整机备份

提供“导出 VM 备份”入口。首版只允许 VM 完全停止后导出，包含 root disk、metadata、boot kit、migration journal 和恢复所需设置快照；共享 Mac 文件夹本身不进入备份。备份采用版本化容器、逐文件 hash 和最终 manifest。

### FR-7：恢复

恢复前验证产品 identity、schema、ABI、大小、hash、所有权和目标空间。目标位置必须为空或为新的 My Omarchy workspace，绝不覆盖现有 active VM。若当前版本可以通过已声明迁移链接收该备份，先恢复原 generation，再按正常升级流程迁移。

### FR-8：Time Machine 合同

文档必须明确 Time Machine 支持状态。除非完成一致性验证，否则不得宣称运行中 VM 的 Time Machine 文件级快照可直接恢复；推荐路径为 App 内离线导出。

## 5. 数据与状态流

```text
active generation
      | APFS clone/full copy
      v
candidate generation -- offline migration --> boot health --> graphical health
      | failure                                      | success
      v                                              v
discard candidate                            atomic promote
                                                     |
                                                     v
                                          previous generation retained
```

host journal 是事务事实源；guest health report 绑定 nonce、target identity 和本次 QEMU 实例。任何 stale report 都不能推动提交。

## 6. 边界情况

| 场景 | 处理方式 |
|------|----------|
| 找不到唯一迁移链 | 保持旧 VM 可启动，说明该 App 不支持升级 |
| 空间不足 | 在创建候选前失败并显示所需/可用空间 |
| 迁移中断 | active 不变；根据 journal 清理或重试 candidate |
| 新代图形会话失败 | 保留旧代并提供回滚 |
| 备份损坏 | 拒绝恢复，不创建半成品 workspace |
| 目标已有 VM | 拒绝覆盖，要求选择新位置 |
| 导入 Try Omarchy 目录 | 因 product identity 不符而明确拒绝 |
| 外置卷在迁移中断开 | 停止 QEMU，active 指针不得改变 |

## 7. 涉及文件

- host storage library、Swift lifecycle/controller/QMP 模块
- guest initramfs hook、runtime package、health service 和 migration runner
- guest artifact manifest、provenance 和 update image builder
- 启动菜单升级/备份/恢复 UI
- lifecycle、断电、故障注入和跨版本真实 VM 测试
- README、架构和恢复文档

## 8. 验收标准

1. 使用至少两个历史 My Omarchy factory 创建并实际 provision 的 VM 升级至当前版本。
2. 升级后用户、测试文件、安装应用、设置和 SSH host key hash 不变。
3. 在 clone、迁移、health、commit 各阶段注入中断，active 旧代始终可恢复。
4. 新代首次图形健康失败时可以一键回滚。
5. UI 正确显示 App、factory、VM runtime、kernel 和迁移状态。
6. 完成“写入数据→导出→删除测试 workspace→恢复→启动→hash 校验”演练。
7. 损坏备份、Try Omarchy 数据和已有目标 VM 均被安全拒绝。
8. 所有删除动作要求明确确认，并仅删除经 metadata 验证的 My Omarchy generation。
