# 本地安全边界加固对齐校验报告

## 1. 校验输入

- 设计：`2026-09-13-local-security-hardening-design.md`
- 功能验证：`verification-cases.md`
- OpenSpec：`openspec-plan.md`
- 当前实现基线：提交 `6e662a2`

## 2. 一致性结论

- Spec 验收项：11/11 已映射到 Task 和可执行 Case。
- P0/P1 风险：全部有负向或竞态 Case。
- OpenSpec Task：10/10 有明确依赖、验收和 Case 映射。
- 范围：没有结构化 diagnostics、数据迁移、可配置阈值或通用框架扩张。
- 结论：允许进入 SDD + TDD 开发。

## 3. 逐项对齐矩阵

| Spec 验收标准 | Task | Case | 结果 |
|---|---|---|---|
| 单日志不超过 10 MiB且只有一次截断标记 | T1、T2 | VC-LOG-002 | 对齐 |
| 受管理日志不超过 10 个/50 MiB | T1、T2 | VC-LOG-003 | 对齐 |
| 目录/文件链接、占位和权限攻击不被跟随 | T1、T2 | VC-LOG-001 | 对齐 |
| 日志失败不阻止 VM | T1、T2、T10 | VC-LOG-001/003、VC-E2E-001 | 对齐 |
| Force Stop 必须确认且状态漂移不 kill | T3、T4 | VC-FORCE-001/002 | 对齐 |
| Home 与外置卷真子目录允许 | T5、T6、T7 | VC-STORAGE-001/003 | 对齐 |
| 其余路径由 Swift/override/shell 拒绝 | T5、T6、T7 | VC-STORAGE-002/003 | 对齐 |
| Storage 在任何目标修改前拒绝 | T7 | VC-STORAGE-003 | 对齐 |
| 旧位置不移动、不删除、不 fallback | T5、T6 | VC-STORAGE-004 | 对齐 |
| host/guest 统一 10 MiB | T8、T9 | VC-CLIP-001/002 | 对齐 |
| focused tests 与 `make test` 通过 | T10 | VC-REG-001 | 对齐 |

## 4. 风险点覆盖复核

| 风险 | 设计控制 | Task | Case |
|---|---|---|---|
| 新日志使 50 MiB 配额失效 | 创建前 9/40 预留，关闭后 10/50 | T1、T2 | VC-LOG-003 |
| 目录 symlink 被 `chmod` 跟随 | 先 `lstat`，再修改，最终复核 | T1、T2 | VC-LOG-001 |
| 文件名碰撞或链接覆盖 | `O_EXCL | O_NOFOLLOW` + `fstat` | T1、T2 | VC-LOG-001 |
| AppKit 模态循环误杀新 session | 捕获并复核 session/state | T3、T4 | VC-FORCE-002 |
| 环境变量绕过 Storage UI | Swift launch config 与 shell 双重校验 | T5–T7 | VC-STORAGE-002/003 |
| 伪造 `$HOME` 扩大白名单 | shell 读取真实账户 Home | T7 | VC-STORAGE-003 |
| 测试要求诱导生产 bypass | 纯策略注入/仓库夹具 | T5、T7 | VC-STORAGE-001/003 |
| 旧 VM 被迁移或误删 | 明确拒绝和只改 preference | T5、T6 | VC-STORAGE-004 |
| host/guest payload 漂移 | 两端边界测试 | T8、T9 | VC-CLIP-001/002 |

## 5. 修复记录

在 Step 3 初版拆解复核中修正以下表达：

1. 将完整 `make test` 与真实 App E2E 分开：前者在代码评审前作为功能 Case，后者按 Dev Loop 在两轮评审后执行。
2. 明确 T7 的测试 fixture 不能变成生产环境变量 bypass。
3. 明确 T10 不负责完整 diagnostics 重构，只负责验证证据与必要文档。
4. 明确 Clipboard 回归同时验证格式和 echo 语义，防止只改常量导致协议回归。

## 6. 最终 Task 顺序

1. T1 → T2：diagnostics red-green-refactor。
2. T3 → T4：Force Stop red-green-refactor。
3. T5 → T6 → T7：Swift 再 shell 的 Storage red-green-refactor。
4. T8 → T9：clipboard 两端 red-green-refactor。
5. T10：focused Case 与完整回归、验证报告。
6. 两轮 code review。
7. VC-E2E-001。
8. 提交、SemVer tag、push。

## 7. Gate

对齐门禁状态：**PASS**。零漏项、零错配、无未决参数，可以进入开发。
