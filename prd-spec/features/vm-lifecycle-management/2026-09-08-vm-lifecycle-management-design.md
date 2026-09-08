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

### 2.1 版本化协议

进入实现前必须冻结并以 JSON Schema 测试以下五个独立协议：

| 协议 | 必填身份字段 | 用途 |
|------|--------------|------|
| `storage-metadata.schema.json` | schemaVersion、productIdentity、workspaceId、activeGeneration、previousGeneration | workspace 与 active pointer 的唯一事实源 |
| `update-manifest.schema.json` | schemaVersion、productIdentity、channel、source/target generation、antiRollbackSequence、payload digest、migration list、signingKeyId | 声明唯一升级链和受信输入 |
| `lifecycle-journal.schema.json` | schemaVersion、transactionId、workspaceId、source/target generation、candidate path、state、sequence、timestamps | 记录 host 事务状态和崩溃恢复 |
| `guest-health-report.schema.json` | protocolVersion、sessionNonce、qemuInstanceId、productIdentity、targetGeneration、bootKitDigest、graphicalState、sequence | 证明本次候选实例健康 |
| `backup-manifest.schema.json` | schemaVersion、productIdentity、workspaceId、generation、createdAt、members、logical/allocated size、digest | 验证离线备份和恢复输入 |

所有 schema 都必须使用明确版本号、拒绝未知 product identity，并有当前版本、缺字段、未知新版本和篡改 fixture；存在上一兼容版本时还必须保留对应 fixture。schema 的兼容窗口由 App 明确声明，不允许“尽力解析”。

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

manifest 采用 RFC 8785 JSON Canonicalization Scheme 规范化后使用 Ed25519 项目 release signing key 签名，key ID 和签名值与 payload 分离存储。App bundle 内置受信公钥集合，只接受来自 `superops-team/my-omarchy` 已批准发布通道的签名；验证必须覆盖 product identity、channel、source/target generation、全部 payload hash、最低 App 版本和单调递增的 `antiRollbackSequence`。密钥轮换必须由仍受信的旧 key 对包含新 key、启用版本和用途的新 key 声明签名；撤销列表随 App 发布。签名无效、key 被撤销或序号倒退时不得运行 migration。

### FR-2：事务升级

升级必须在 active disk 的 APFS clone 上执行；若 clone 不可用则允许用户选择有足够空间的 full copy，不得原地修改 active disk。候选盘使用目标 boot kit 进行隔离的离线迁移和健康检查。只有以下条件全部满足才可原子提升：

1. manifest/hash 验证；
2. 所有迁移脚本成功；
3. 离线文件系统检查通过；
4. boot health 成功；
5. 图形会话 health 成功；
6. QEMU 干净退出；
7. host journal 完整提交。

候选健康检查使用 qualification-only 启动模式：不挂载共享目录、不开放用户端口、不恢复普通用户会话自动启动项。guest health service 必须同时证明 kernel/userspace 已启动、目标 runtime generation 匹配、systemd 达到 graphical target、compositor ready 且 input round-trip probe 成功。host 验证绑定的 health report 后通过 QMP 发起关机，并以 guest shutdown 事件和 QEMU exit status 0 共同判定干净退出；用户无需进入候选桌面。

### FR-3：回滚窗口

前一代 VM 至少保留到新代完成一次图形启动并被用户使用后正常关机。若新代无法启动，UI 提供回滚。完成验证后再提示用户回收旧代空间，不自动静默删除。

### FR-4：迁移脚本安全边界

迁移脚本由 release 签名输入生成，使用受限环境、固定工具路径、无网络、最小挂载权限执行。每个 migration ID 只能成功记录一次，必须具备 verify/apply 语义和幂等重试能力。用户控制的 guest 状态只能提供 health 信号，不能决定 host 激活路径。

### FR-5：版本展示

启动菜单显示 App version、bundled factory、active VM runtime、kernel 和状态：最新、可升级、升级中、回滚可用、不兼容。不得只显示 App 版本。

### FR-6：整机备份

提供“导出 VM 备份”入口。首版只允许 VM 完全停止后导出，包含 root disk、metadata、boot kit、migration journal 和恢复所需设置快照；共享 Mac 文件夹本身不进入备份。

备份采用目录型版本化容器 `<name>.myomarchyvm`，内部含 `backup-manifest.json`、保留稀疏属性的 root disk、metadata、boot kit 和 settings。导出先写入同一目标卷的 `<name>.myomarchyvm.partial`，逐成员计算 SHA-256 并校验 manifest 后，使用同卷原子 rename 提交；任何中断只留下不可导入的 `.partial`。导出前按源文件 allocated size、非稀疏成员和 10% 安全余量计算所需空间。实现必须使用 APFS clone 或能够保留 sparse extent 的复制方式，禁止无提示地把 logical 24 GiB 展开为完全分配文件。

### FR-7：恢复

恢复前验证产品 identity、schema、ABI、容器不是 `.partial`、成员大小、hash、所有权和目标空间。目标位置必须不存在或为空，恢复过程创建新的 workspace ID，绝不覆盖、合并或复用现有 active VM。恢复同样先写临时 workspace，完整验证后原子提交。若当前版本可以通过已声明迁移链接收该备份，先恢复原 generation，再按正常升级流程迁移；冲突时只能要求选择新位置或取消，首版不提供覆盖/合并选项。

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

### 5.1 Host journal 状态机

状态只能按以下顺序前进：

`prepared -> cloned -> migrated -> offlineVerified -> candidateBooting -> guestHealthy -> shutdownVerified -> committed -> previousRetained`

- journal 每次转移先写临时文件，执行 `fsync(file) -> atomic rename -> fsync(parent directory)`，并递增 sequence；active pointer 也使用相同原子写协议。
- `committed` 是唯一允许改变 active pointer 的状态。提交顺序固定为：持久化 `shutdownVerified`、原子更新 active pointer、持久化 `committed`；恢复器必须能识别“pointer 已更新但 committed 尚未落盘”，通过 transaction ID 和 generation identity 收敛为 committed，不能回写旧盘内容。
- App 重启遇到 `prepared/cloned/migrated/offlineVerified/candidateBooting/guestHealthy` 时，active 保持 source，并允许安全重试或清理 candidate；遇到 `shutdownVerified` 时重新验证 candidate 后继续提交；遇到 `committed/previousRetained` 时从 target 启动并保留 previous。
- candidate 清理只能删除 journal 记录的路径，且该目录的 product identity、workspace ID、target generation 和 transaction ID 必须全部匹配。

### 5.2 跨版本测试资产

稳定版验收固定使用 `source-v1`、`source-v2`、`target-v3` 三代签名 fixture。Phase 2 发布并封存 v1；后续 prerelease 必须至少封存 v2；Phase 5 以当前目标版本构建 v3。每代保存 DMG、factory、update manifest、checksum、provenance、schema fixture 和确定性的 provision 脚本，不得以临时重新构建的旧版本代替历史制品。

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
| health report nonce 或实例不匹配 | 作为 stale/伪造报告拒绝，candidate 不得 promote |
| update manifest 签名错误或序号倒退 | 在创建 candidate 前拒绝，不执行任何 migration |
| 导出中断或目标空间不足 | 保留或清理 `.partial`，不得出现可导入的半成品 |

## 7. 涉及文件

- host storage library、Swift lifecycle/controller/QMP 模块
- guest initramfs hook、runtime package、health service 和 migration runner
- guest artifact manifest、provenance 和 update image builder
- 启动菜单升级/备份/恢复 UI
- lifecycle、断电、故障注入和跨版本真实 VM 测试
- README、架构和恢复文档

## 8. 验收标准

1. 使用封存的 `source-v1`、`source-v2` factory 创建并实际 provision 的 VM，分别升级至 `target-v3`；三代 fixture 均能追溯到签名、checksum 和 provenance。
2. 升级后用户、测试文件、安装应用、设置和 SSH host key hash 不变。
3. 对 journal 每个非终态以及 active pointer 更新前后注入崩溃；恢复结果符合状态矩阵，提交前 source 始终保持 active 且可启动。
4. 错误 nonce、错误实例、错误 generation、graphical/input probe 失败或 QEMU 非零退出均不能 promote；新代失败时可以一键回滚。
5. UI 正确显示 App、factory、VM runtime、kernel 和迁移状态。
6. 完成“写入数据→离线导出→删除测试 workspace→恢复到新 workspace→启动→hash 校验”演练；稀疏盘不会无提示完全展开，导出中断只产生不可导入的 `.partial`。
7. 损坏备份、Try Omarchy 数据和已有目标 VM 均被安全拒绝。
8. 所有删除动作要求明确确认，并仅删除经 metadata 验证的 My Omarchy generation。
9. update manifest 的错误签名、撤销 key、错误 product/channel、篡改 payload 和 anti-rollback 序号倒退全部在 migration 前被拒绝。
10. 五个版本化 schema 均通过当前、缺字段、未知版本和篡改 fixture 的契约测试；存在上一兼容版本时，同时通过该版本 fixture。
