# My Omarchy 产品就绪路线图

## 1. 概述

### 1.1 动机

My Omarchy 要从当前仓库演进为 `superops-team/my-omarchy` 独立维护和发布的轻量 macOS Omarchy VM。工作同时涉及产品身份、品牌资产、运行时资源、磁盘回收、无损升级、备份恢复、诊断和真实设备发布验证。若一次性混合实施，容易产生持久化 ABI 冲突、旧产品误操作和无法审查的超大变更。

### 1.2 目标

本路线图统一五份专题 PRD 的依赖、阶段、门禁和完成定义。每个阶段必须形成可运行、可验证的闭环，后续阶段不能绕过前置产品身份或数据安全合同。

## 2. 关联专题

| 专题 | 文档 | 核心产出 |
|------|------|----------|
| 产品基础 | `prd-spec/features/my-omarchy-product-foundation/2026-09-08-my-omarchy-product-foundation-design.md` | 全新身份、Logo、命名空间、独立数据边界 |
| 发布门禁 | `prd-spec/features/release-quality-gate/2026-09-08-release-quality-gate-design.md` | 最终 DMG、真实 Mac E2E、发布证据 |
| 轻量运行时 | `prd-spec/features/lightweight-vm-runtime/2026-09-08-lightweight-vm-runtime-design.md` | 自适应资源、trim、性能预算 |
| 生命周期 | `prd-spec/features/vm-lifecycle-management/2026-09-08-vm-lifecycle-management-design.md` | My Omarchy 跨版本升级、回滚、备份恢复 |
| 诊断恢复 | `prd-spec/features/diagnostics-and-recovery/2026-09-08-diagnostics-and-recovery-design.md` | 日志、错误分类、诊断包和安全动作 |

## 3. 架构原则

1. My Omarchy 是全新产品，不迁移 Try Omarchy 数据。
2. `superops-team/my-omarchy` 是唯一下载、Issue、源码和发布源。
3. host metadata 是持久化和激活事实源，guest report 只能提供受绑定的健康信号。
4. 所有破坏性动作必须明确确认、精确定位且可由 metadata 验证。
5. 所有性能和兼容性声明必须有真实设备证据。
6. App 更新、My Omarchy runtime 更新与普通 Omarchy 包更新是三个不同通道。
7. 版本、schema、ABI、迁移和 release evidence 均机器可读。

## 4. 实施阶段

### Phase 0：冻结合同与建立基线

产出：

- 保存当前测试、性能、磁盘和真实运行基线。
- 把现有未提交输入法工作独立收口，不与全面改名混在同一提交。
- 建立允许的历史引用清单和 My Omarchy identity 常量表。
- 修复本地 `make doctor` 无法发现 Swift `Testing` 模块缺失的问题。

退出门禁：工作树干净；当前主线测试结论明确；旧产品路径清单完成。

### Phase 1：My Omarchy 产品身份与品牌

产出：

- 完成新 Logo 和品牌资产。
- 全面替换 App、bundle、数据、guest ABI、构建与文档命名。
- 更新所有仓库和支持链接。
- 建立 My Omarchy v1 factory 和 storage identity。

退出门禁：与 Try Omarchy 并行安装和数据隔离测试通过；旧 mark 不再进入产物；语义扫描只剩允许的历史引用。

### Phase 2：发布门禁最小闭环

产出：

- 单一 release 命令、版本/tag、clean build、签名、公证、Gatekeeper 和 checksum。
- 至少一台真实 Apple Silicon Mac 对最终 DMG 完成 P0 E2E。
- 发布 `release-evidence.json`。

退出门禁：能够从 `superops-team/my-omarchy/releases` 下载并验证第一个 My Omarchy prerelease。

### Phase 3：轻量运行时

产出：

- 自动资源档。
- discard/fstrim 和空间展示。
- idle、启动、sleep、1080p30 性能基线。

退出门禁：8 GiB/16 GiB 支持设备通过资源和空间回收标准，性能报告进入发布证据。

### Phase 4：诊断与恢复

产出：

- 结构化错误、持久日志、脱敏诊断包。
- 阶段性启动健康与故障注入。
- 对应错误的非破坏性恢复动作。

退出门禁：P0/P1 故障均有准确错误码、日志和安全动作，未知错误不再默认建议重装。

### Phase 5：生命周期升级与备份

产出：

- 从第一个 My Omarchy prerelease 到后续版本的事务升级。
- 健康检查、回滚窗口、升级 journal。
- 离线备份与恢复。

退出门禁：至少两个历史 My Omarchy factory 的真实 VM 完成升级；中断注入和完整恢复演练通过。

### Phase 6：稳定版资格

产出：

- 最低和最新 macOS、两个芯片代际的支持矩阵。
- 全部 P0 E2E、性能、升级、备份、诊断和品牌合规证据。
- 清晰的已知限制和安全报告流程。

退出门禁：满足第 7 节统一 Definition of Done，才允许发布 1.0。

## 5. 依赖关系

```text
Phase 0 基线
    |
    v
Phase 1 产品身份 ----> Phase 2 发布门禁
    |                       |
    +----> Phase 3 轻量运行时
    |                       |
    +----> Phase 4 诊断恢复 +----> Phase 5 生命周期
                                    |
                                    v
                              Phase 6 稳定版
```

生命周期升级必须以已经发布的 My Omarchy prerelease 为 source generation，因此不能早于 Phase 2。诊断与健康信号是安全提交和回滚的基础，因此 Phase 5 依赖 Phase 4。

## 6. 变更与提交边界

每个阶段单独分支和评审，至少按以下边界拆分：

1. 文档与 identity 常量；
2. 品牌资产；
3. host bundle/路径；
4. guest ABI 与 artifact；
5. 测试和旧引用清理；
6. 各专题功能。

不得把用户当前输入法改动、Logo 二进制资产和生命周期框架塞入同一提交。每次持久化 schema 或 boot ABI 变更都要有独立设计和兼容结论。

## 7. 统一 Definition of Done

My Omarchy 1.0 只有在以下条件全部满足时才算产品就绪：

1. 唯一维护源、品牌、Logo、bundle、guest ABI 和数据目录全部为 My Omarchy。
2. My Omarchy 不读取、修改或删除 Try Omarchy 数据，并可与其并行安装。
3. release gate 不能绕过测试、真实设备 E2E、签名、公证、Gatekeeper 和证据生成。
4. 支持矩阵覆盖最低和最新 macOS、至少两个 Apple Silicon 代际。
5. 默认 CPU/RAM、idle、启动、sleep、磁盘 trim 和视频基线达到批准预算。
6. 已发布 My Omarchy VM 可无损升级，失败可回滚。
7. VM 可以离线备份并在空 workspace 完整恢复。
8. 高频故障有结构化错误、脱敏日志和安全恢复动作。
9. 所有下载、Issue、安全报告和版本来源指向 `superops-team/my-omarchy`。
10. README、架构、发布说明和实际代码合同一致。

## 8. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 全面改名遗漏内部 ABI | identity 清单、允许列表和全仓合同扫描 |
| 品牌与官方 Omarchy 混淆 | 独立 Logo、非官方声明和商标近似审查 |
| 生命周期设计过大 | 先发布 prerelease，再只支持 My Omarchy generation |
| 性能指标受设备噪声影响 | 同设备固定场景三次中位数比较 |
| E2E 人工项不可审计 | 结构化记录设备、执行者、步骤和结果 |
| 误删旧产品数据 | 新 identity、新根目录、生产代码禁止探测旧路径 |

## 9. 验证计划

- 每个专题按自身验收标准完成单元、契约、集成和真实设备验证。
- 每阶段结束执行全仓名称、路径、链接、版本和文档一致性扫描。
- 每个 prerelease 保存 DMG、SHA-256、provenance、E2E 和性能报告，作为后续升级 source fixture。
- 1.0 前进行一次从全新安装到升级、备份、恢复、Reset、卸载的完整生命周期演练。

## 10. 分层任务与交付物

| 层级 | 任务 | 交付物 | 依赖 |
|------|------|--------|------|
| 产品与品牌 | identity 清单、Logo、资产和退役说明 | 品牌包、identity contract、文档 | Phase 0 |
| Host 基础 | bundle、路径、设置、socket、版本来源 | 可并行安装的 My Omarchy App | 产品身份 |
| Guest 基础 | 包、repo、路径、kernel 参数、virtio port | My Omarchy factory v1 | 产品身份 |
| 发布工程 | preflight、签名、公证、证据、E2E | 可下载 prerelease | Host/Guest v1 |
| 运行时 | resource profile、discard、trim、benchmark | 轻量运行报告 | prerelease 基线 |
| 可观测性 | 日志、错误模型、诊断包、health | 故障注入报告 | Host/Guest v1 |
| 生命周期 | update manifest、candidate、journal、rollback | 两代 VM 升级证明 | 发布工程、health |
| 数据保护 | export/import、hash、恢复演练 | 备份格式和恢复报告 | storage identity |

## 11. 预估排期

以下为 1 名熟悉仓库的主开发者的工程量级，不是承诺日期；真实 Mac 设备、签名和商标审查等待时间单独计算。

| 阶段 | 预计工程周 | 里程碑 | 风险缓冲 |
|------|------------|--------|----------|
| Phase 0 | 0.5–1 | 干净基线、identity 清单 | toolchain 与现有输入法变更 |
| Phase 1 | 2–3 | My Omarchy App/factory v1、品牌资产 | 全仓 ABI 改名、Logo 审查 |
| Phase 2 | 1.5–2.5 | 首个签名 prerelease 和 E2E evidence | 公证、设备可用性 |
| Phase 3 | 1.5–2 | 资源/trim/性能门禁 | APFS discard 行为、性能噪声 |
| Phase 4 | 2–3 | 结构化诊断与故障恢复 | 跨进程日志和错误归因 |
| Phase 5 | 4–6 | 两代升级、回滚、备份恢复 | 数据一致性和中断恢复 |
| Phase 6 | 1–2 | 支持矩阵和 1.0 资格审查 | 多设备回归与缺陷修复 |

建议总量为 12.5–19.5 工程周。Phase 1–2 完成后即可发布明确标注限制的 prerelease；1.0 必须等待 Phase 6。
