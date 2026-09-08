# My Omarchy Phase 0 与 Phase 1A 实施设计

## 1. 概述

### 1.1 背景

My Omarchy 已确定为与 Try Omarchy 完全独立的新产品。产品身份、发布来源和后续能力已由专题 PRD 定义，但当前实现仍广泛使用 Try Omarchy 的名称、bundle ID、数据路径、guest ABI、构建资源和测试夹具。直接进行全仓替换会同时触碰 host、guest、持久化数据和构建系统，既难以审查，也容易误删旧产品数据或形成半新半旧的协议。

本设计只覆盖产品路线图中的 Phase 0 和 Phase 1A：先取得可信基线，再建立机器可读、可测试的产品身份合同。它不执行 Logo 设计、Host Identity 替换或 Guest ABI 替换；这些工作分别属于 Phase 1B、1C、1D。

### 1.2 目标

1. 建立可重复的本地与 CI 测试基线，并修复 `make doctor` 无法发现 Swift `Testing` 模块缺失的问题。
2. 建立 My Omarchy 唯一机器可读 identity contract，覆盖产品、仓库、macOS、存储、guest ABI、构建和发布命名。
3. 建立语义化旧身份扫描器，阻止新增 Try Omarchy 身份，并为 Phase 1B–1D 提供可逐项清零的迁移清单。
4. 明确用户现有输入法/键盘改动与产品改名工作的隔离边界。
5. 让后续 Host、Guest、品牌和发布实现都引用同一个已评审合同，不在各模块重新决定名称。

### 1.3 非目标

- 不在本阶段重命名 App、Swift module、可执行文件、guest 文件或运行时端口。
- 不创建最终 Logo 或 AppIcon。
- 不读取、迁移、修改或删除 Try Omarchy 本机数据。
- 不修改用户当前未提交的 Fcitx5、SDDM、键盘布局和 guest package 变更。
- 不实现 release candidate、生命周期、诊断或性能功能。

## 2. 基线与约束

### 2.1 实施起点

实施分支必须基于包含以下文档提交的主线：

- `f5f1ae2 docs: define My Omarchy product readiness specs`
- `2023c4a docs: resolve My Omarchy spec review gaps`

开始 Phase 0 前，当前 guest 输入法/键盘工作必须由其 owner 在独立提交或独立工作树中收口。Phase 0 不得通过 stash、reset、checkout 或删除文件替用户处理这些改动。若主工作树仍不干净，应新建独立 worktree 执行本计划。

### 2.2 当前事实

- `make test` 包含 Python、guest、shell 和 Swift 测试。
- 当前环境可能存在 `swift` 可执行文件但缺少可编译的 `Testing` module；现有 `make doctor` 无法发现该情况。
- 旧身份分布于 `Makefile`、macOS Swift package、App bundle、构建脚本、存储脚本、guest manifest/overlay、测试和文档。
- 当前 `make clean-all` 会操作 Try Omarchy 路径。在 Phase 1C 完成之前，不得把它作为 My Omarchy 清理能力验收，也不得在本计划中运行。

## 3. 方案设计

### 3.1 单一身份合同

新增 `config/product-identity.json`，作为产品命名的唯一设计时事实源。v1 必须包含以下稳定字段：

```json
{
  "schemaVersion": 1,
  "product": {
    "displayName": "My Omarchy",
    "slug": "my-omarchy",
    "compactName": "MyOmarchy"
  },
  "repository": {
    "owner": "superops-team",
    "name": "my-omarchy",
    "url": "https://github.com/superops-team/my-omarchy",
    "releasesUrl": "https://github.com/superops-team/my-omarchy/releases",
    "issuesUrl": "https://github.com/superops-team/my-omarchy/issues"
  },
  "macos": {
    "bundleIdentifier": "team.superops.myomarchy",
    "appBundleName": "My Omarchy.app",
    "executableName": "my-omarchy",
    "moduleName": "MyOmarchy",
    "bundledQemuExecutableName": "My Omarchy",
    "preferencesName": "team.superops.myomarchy.plist",
    "cacheDirectory": "team.superops.myomarchy",
    "savedStateName": "team.superops.myomarchy.savedState"
  },
  "storage": {
    "applicationSupportRelativePath": "My Omarchy/VM/v1",
    "productIdentity": "my-omarchy"
  },
  "guest": {
    "kernelParameterPrefix": "myomarchy.",
    "packagePrefix": "my-omarchy-",
    "repositoryName": "my-omarchy",
    "shareDirectory": "/usr/share/my-omarchy",
    "libraryDirectory": "/usr/local/lib/my-omarchy",
    "artifactKind": "my-omarchy-guest-artifacts"
  },
  "runtime": {
    "servicePrefix": "team.superops.myomarchy.",
    "virtioPortPrefix": "team.superops.myomarchy.",
    "dockerPrefix": "my-omarchy-"
  },
  "release": {
    "dmgPattern": "MyOmarchy-<semver>-arm64.dmg",
    "guestArtifactPattern": "my-omarchy-guest-<semver>-arm64",
    "notaryProfileDefault": "my-omarchy"
  }
}
```

该文件是设计与测试合同，不要求 Swift 或 shell 在运行时解析 JSON。Phase 1C/1D 应把值编译或写入各自模块，并由契约测试反向核对 JSON；这样避免把启动可靠性绑定到仓库外部配置文件。

### 3.2 旧身份清单与扫描模式

新增 `config/legacy-identity-allowlist.json` 和 `scripts/verify-product-identity.py`。扫描器识别以下旧身份类别，而不是只做一个宽泛字符串替换：

| 类别 | 典型值 | Phase 1 归属 |
|------|--------|--------------|
| 用户品牌 | `Try Omarchy`、`TryOmarchy` | 1B/1C |
| 仓库与发布 | `themartiano/try-omarchy` | 1A/文档 |
| macOS 身份 | `dev.tryomarchy.*`、旧 App/binary/module 名 | 1C |
| host 存储 | 旧 Application Support、Cache、Preferences、Saved State | 1C |
| guest ABI | `tryomarchy.*`、`try-omarchy-*`、virtio port | 1D |
| 构建资源 | Docker image、volume label、临时目录、artifact kind | 1D |
| 历史归属 | LICENSE、THIRD_PARTY_NOTICES 和迁移说明 | 永久允许但精确审计 |
| 验证夹具 | scanner 测试中刻意构造的旧 identity | 永久允许但精确审计 |

allowlist 的每个条目必须包含 `path`、`pattern`、`expectedCount`、`category`、`ownerPhase` 和 `reason`。不允许目录级通配忽略；路径必须是仓库相对路径，pattern 必须匹配完整身份 token，计数必须精确。新增旧标识、删除后仍残留无效 allowlist、计数变化或未登记文件都必须失败。

扫描器提供两种模式：

- `baseline`：允许当前已登记旧身份，但禁止新增、漂移和无 owner 条目。Phase 1A 合并后 PR CI 使用该模式。
- `release`：仅允许 LICENSE、THIRD_PARTY_NOTICES、明确历史说明以及 scanner 自身负向测试中的必要引用。Phase 1B–1D 每完成一项就删除对应 allowlist；Phase 1 完成与发布门禁使用该模式。

扫描范围仅包含 `git ls-files` 返回的受版本控制文本文件，排除构建输出和二进制；是否为文本由读取解码与 NUL 检测决定，而不是目录级忽略。当前用户未提交的新文件在归属明确并提交后才进入清单，Phase 1A 不猜测或修改其内容。

### 3.3 Toolchain doctor

`make doctor` 除现有命令存在性检查外，必须在临时目录编译最小 Swift probe：

```swift
import Testing

@Test func probe() {}
```

probe 使用与 `make test` 相同的 deployment target 和 module cache 环境；编译失败时在运行完整测试前返回非零，并明确报告 Swift toolchain 无法提供 `Testing` module。临时目录由 `mktemp -d` 创建并通过 trap 清理，不写入仓库或用户全局配置。

为使该行为可测试，把检查实现为独立脚本 `scripts/doctor.sh`，支持通过 PATH 注入测试替身，但生产模式仍执行真实 `uname`、`sw_vers`、Docker 和 Swift probe。Makefile 的 `doctor` 只调用该脚本，避免复杂 shell 逻辑继续堆积在 recipe 中。

### 3.4 基线证据

Phase 0 生成 `docs/baselines/phase-0.md`，记录：

- commit、macOS、芯片、Swift/Xcode、Docker 和 QEMU 版本；
- `make doctor`、`make test` 各测试组结果及失败原因；
- 当前 App/factory identity 和 artifact digest；
- 冷启动、空闲 CPU、宿主 memory pressure、raw logical/allocated bytes 的测量方法与结果；
- 尚未具备的真实设备/E2E 项，不得填为通过。

基线文档只保存脱敏后的环境信息，不记录用户名、HOME 绝对路径、证书名称或密钥配置。性能数据在 Phase 3 只作为对照，不自动成为最终阈值。

## 4. 实施步骤

### Task 0.1：隔离工作树与记录实施起点

涉及范围：Git 工作树和本计划，不修改产品文件。

1. 确认 guest 输入法/键盘改动已由 owner 独立提交或位于其他 worktree。
2. 从包含 `2023c4a` 的主线创建 Phase 0/1A 分支或 worktree。
3. 保存 `git status --short` 和 `git rev-parse HEAD`，确认实施工作树干净。

验证：实施工作树没有无关改动；原工作树中的用户文件仍存在且内容不变。

提交边界：无产品提交；若需工作树操作，仅创建隔离环境。

### Task 0.2：以测试先行修复 doctor

涉及文件：

- 新增 `scripts/doctor.sh`
- 新增 `tests/test-doctor.py`
- 修改 `Makefile`

TDD 顺序：

1. 写入失败测试：模拟 `swift` 存在但 `import Testing` 编译失败，断言 doctor 返回非零且包含稳定错误信息。
2. 写入通过测试：注入成功的工具替身，断言所有检查执行且临时文件被清理。
3. 实现 `scripts/doctor.sh` 并让 `make doctor` 调用它。
4. 在真实环境运行 `make doctor`，保留实际成功或预期失败结果。

验收：缺少 `Testing` module 时必须在 `make test` 前失败；doctor 不修改全局 Swift 配置。

建议提交：`test: make doctor verify Swift Testing support`

### Task 0.3：采集可复现基线

涉及文件：

- 新增 `docs/baselines/phase-0.md`
- 仅在发现错误文档命令时修改对应说明

步骤：

1. 运行 `make doctor`。
2. 运行 `make test`，逐组记录结果；失败不得改写为通过。
3. 若本机已有可信构建产物，记录 artifact digest 和静态 identity；若没有，明确记录“未采集”，不为生成基线擅自发布或签名。
4. 采集一次非发布的启动、空闲 CPU、memory pressure 和磁盘占用基线；无法安全执行的真实设备步骤记录为缺口。

验收：另一位开发者能按文档重复命令并理解哪些结果已验证、哪些尚未验证。

建议提交：`docs: record pre-migration product baseline`

### Task 1A.1：建立 identity contract

涉及文件：

- 新增 `config/product-identity.json`
- 新增 `config/product-identity.schema.json`
- 新增 `tests/test-product-identity.py`

TDD 顺序：

1. 写 schema fixture 测试，覆盖当前合法合同、缺字段、额外字段、错误 URL、旧 bundle ID、非 My Omarchy guest namespace。
2. 写跨字段不变量测试：repository URL、Releases、Issues 必须同属 `superops-team/my-omarchy`；所有技术前缀符合已批准值。
3. 加入合同 JSON 和 schema，使测试通过。

校验脚本的必需路径只使用 Python 标准库完成字段集合、类型、格式和跨字段不变量检查；仓库不因本任务新增运行时 Python 包依赖。标准 JSON Schema 仍作为工具可消费的合同保存，并在 CI 明确安装锁定版本的 validator 后执行第二次校验，不能依赖 runner 恰好预装的 `jsonschema`。

验收：合同与产品基础 PRD 逐字段一致；`additionalProperties` 默认拒绝，避免未审查字段悄然进入合同；全新 Python 环境仍可执行本地必需门禁。

建议提交：`docs: add machine-readable My Omarchy identity contract`

### Task 1A.2：建立语义扫描器与 baseline allowlist

涉及文件：

- 新增 `config/legacy-identity-allowlist.json`
- 新增 `config/legacy-identity-allowlist.schema.json`
- 新增 `scripts/verify-product-identity.py`
- 扩充 `tests/test-product-identity.py`

TDD 顺序：

1. 用临时 Git 仓库 fixture 验证未登记旧标识失败。
2. 验证精确 path/pattern/count 的 baseline 条目通过。
3. 验证目录通配、缺少 ownerPhase/reason、过期条目、计数变化失败。
4. 验证 `release` 模式拒绝技术旧身份，只允许精确登记的许可证/历史来源。
5. 从当前干净提交生成初始 baseline allowlist，并人工按 1B、1C、1D 分类；生成工具不能自行批准条目。

验收：新增任意旧品牌、旧 bundle ID、旧数据路径、旧 guest token 或旧仓库入口都会使扫描失败；删除源码旧引用后必须同步删除 allowlist 条目。

建议提交：`test: enforce My Omarchy identity migration inventory`

### Task 1A.3：接入本地和 CI 门禁

涉及文件：

- 修改 `Makefile`
- 修改 `.github/workflows/ci.yml`
- 修改 `CONTRIBUTING.md`
- 新增或更新 `docs/identity.md`

步骤：

1. 新增 `make verify-identity`，默认执行 `baseline` 模式。
2. 新增 `make verify-release-identity`，执行严格 `release` 模式；Phase 1A 时预期失败，并输出按 ownerPhase 汇总的剩余项，而不是接入普通 PR 必须通过的 job。
3. 将 `make verify-identity` 加入 `make test` 和 CI。
4. 文档说明合同字段、allowlist 审批、Phase 1B–1D 清零方式和禁止无差别替换原则。

验收：PR 新增旧身份时 CI 失败；严格模式准确列出尚未完成的 Phase 1B/1C/1D 项；CI 不扫描未跟踪文件或生成物。

建议提交：`ci: enforce My Omarchy identity baseline`

### Task 1A.4：Phase 1A 收口

涉及文件：仅限前述合同、扫描、测试和文档；不修改 Host/Guest 生产身份。

步骤：

1. 运行 `make doctor`、`make verify-identity` 和 `make test`。
2. 运行 `make verify-release-identity`，把预期失败按 1B/1C/1D 数量记录在 Phase 0 基线；严格模式的失败在 Phase 1A 是迁移清单，不是伪装成通过。
3. 执行 `git diff --check` 和变更范围审计。
4. 确认所有新增旧引用测试都会失败，合同值与 PRD 完全一致。

验收：Phase 1A 后主线禁止旧身份继续扩散，同时后续三个阶段拥有明确、可计数、可逐步清零的工作队列。

建议提交：`docs: close My Omarchy identity contract phase`

## 5. 测试矩阵

| 层级 | 测试 | 预期 |
|------|------|------|
| Doctor 单元 | Swift 存在、Testing 缺失 | 非零退出，说明 module 不可用 |
| Doctor 单元 | 所有工具替身可用 | 成功且无残留临时目录 |
| Identity schema | 合法 v1 contract | 通过 |
| Identity schema | 缺字段、额外字段、旧 bundle ID | 失败并指出字段 |
| Scanner 单元 | 新增未登记 `Try Omarchy` | baseline/release 均失败 |
| Scanner 单元 | 精确登记的当前技术旧身份 | baseline 通过、release 失败 |
| Scanner 单元 | LICENSE 中登记的历史归属 | baseline/release 均通过 |
| Scanner 单元 | allowlist 计数或路径漂移 | 失败，要求删除或重新评审条目 |
| Repo 集成 | `make verify-identity` | Phase 1A 主线通过 |
| Repo 集成 | `make verify-release-identity` | Phase 1A 明确失败并按 1B/1C/1D 汇总；Phase 1 完成后通过 |
| 全量回归 | `make test` | 除已记录且获批准的环境阻断外全部通过 |

## 6. 提交与依赖顺序

```text
隔离用户 guest 改动
        |
        v
doctor TDD ----> Phase 0 基线
                      |
                      v
              identity contract
                      |
                      v
            scanner + baseline allowlist
                      |
                      v
                Makefile + CI gate
                      |
          +-----------+-----------+
          v           v           v
     Phase 1B     Phase 1C     Phase 1D
      品牌         Host         Guest
```

每个建议提交必须只包含自身任务文件。尤其禁止把当前 guest 输入法/键盘变更、Logo 二进制、Host rename 或 Guest ABI rename 带入 Phase 0/1A 提交。

## 7. 风险与控制

| 风险 | 控制 |
|------|------|
| baseline allowlist 固化技术债 | 每条必须有 ownerPhase 和精确计数；严格模式持续报告剩余项 |
| 文本扫描误报 | 按 token 分类、精确 pattern 和人工批准处理，不做目录忽略 |
| 文本扫描漏掉二进制 metadata | Phase 1C/1D 另做构建产物 introspection；Phase 1A 不宣称 release-ready |
| JSON 成为运行时单点故障 | 仅作为设计时合同和测试源，不在 App 启动时读取仓库文件 |
| JSON Schema validator 成为隐式环境依赖 | 本地必需校验使用标准库；CI 显式安装锁定版本做标准 schema 复验 |
| 用户未提交改动被混入 | 独立 worktree、逐文件暂存、提交前核对 name-only |
| doctor 测试依赖本机工具 | 单元测试使用 PATH 替身，另保留一次真实机验证 |

## 8. 完成定义

Phase 0 与 Phase 1A 仅在以下条件全部满足时完成：

1. `make doctor` 能真实编译 `import Testing` probe，并对缺失模块 fail closed。
2. 基线文档记录实际成功、失败和未验证项，不包含敏感本机路径或凭据。
3. `config/product-identity.json` 与产品基础 PRD 的全部 v1 值一致并通过 schema 测试。
4. 当前所有受版本控制的旧身份均进入精确 baseline allowlist，且每项有类别、原因、计数和 1B/1C/1D owner。
5. `make verify-identity` 和 CI 能阻止任何新增或漂移的旧身份。
6. `make verify-release-identity` 在 Phase 1A 能准确报告未清零项，并在 Phase 1B–1D 完成后无需改代码即可转为通过。
7. `make test` 通过，或仅保留基线中已明确记录且不由本变更引入的环境阻断。
8. 所有提交均不包含用户现有 Fcitx5、SDDM、键盘布局或 guest package 变更。
9. 未执行任何 Try Omarchy 数据探测、迁移、清理或删除操作。

## 9. 后续阶段入口

Phase 1A 完成后：

- Phase 1B 只处理新 Logo、AppIcon、品牌测试板和合规记录，并清除品牌类 allowlist。
- Phase 1C 只处理 macOS bundle、module/executable、host 路径、偏好、socket、TCC 文案和 host 测试，并清除 host 类 allowlist。
- Phase 1D 只处理 guest package/repo/path、kernel token、virtio port、artifact、Docker 资源和 guest 测试，并清除 guest/build 类 allowlist。
- 三个阶段全部完成后，`make verify-release-identity` 必须通过，才能进入 Phase 2 release candidate 实现。
