# My Omarchy 产品基础与品牌身份设计文档

## 1. 概述

### 1.1 背景

当前仓库源自 Try Omarchy，但维护组织、下载地址、产品名称、macOS bundle、guest 包、内核参数和持久化目录仍混用 `Try Omarchy`、`try-omarchy`、`tryomarchy` 与 `dev.tryomarchy`。这会造成发行归属不清、品牌资产不可控、版本来源无法追溯，也会让后续升级协议继续继承旧产品的兼容负担。

My Omarchy 被定义为全新独立产品，不是 Try Omarchy 的升级版。唯一代码、Issue、下载与发布来源为：

`https://github.com/superops-team/my-omarchy`

My Omarchy 不读取、不迁移、不修改、不删除 Try Omarchy 的应用数据、VM、偏好、日志或 macOS 权限记录。两个产品必须可以在同一台 Mac 上独立安装和运行。

### 1.2 目标

1. 建立唯一、完整且机器可验证的 My Omarchy 产品身份。
2. 创建不依赖旧 Omarchy 官方图形资产的独立 Logo 和视觉系统。
3. 全面替换用户可见品牌及内部技术命名空间。
4. 以新的 schema、ABI、bundle ID 和数据根目录启动产品，不继承 Try Omarchy 兼容协议。
5. 在文档中明确 Try Omarchy 不再由本项目维护，旧产品仅作为历史来源说明。

### 1.3 非目标

- 不迁移 Try Omarchy 的 VM 或设置。
- 不复用 Try Omarchy 的 bundle ID、数据目录或隐私授权。
- 不删除用户机器上的 Try Omarchy。
- 不保证 My Omarchy 可以启动 Try Omarchy 创建的磁盘。
- 不在本阶段改变上游 Basecamp Omarchy 的产品名称、代码或许可证归属。

## 2. 产品身份契约

| 维度 | My Omarchy 唯一值 |
|------|-------------------|
| 产品名 | `My Omarchy` |
| 仓库 | `superops-team/my-omarchy` |
| 官网/项目入口 | `https://github.com/superops-team/my-omarchy` |
| Releases | `https://github.com/superops-team/my-omarchy/releases` |
| Issues | `https://github.com/superops-team/my-omarchy/issues` |
| macOS bundle ID | `team.superops.myomarchy` |
| App 包名 | `My Omarchy.app` |
| Swift package/module | `MyOmarchy` |
| host 可执行文件 | `my-omarchy` |
| App 内 QEMU 可执行文件 | `My Omarchy` |
| DMG | `MyOmarchy-<semver>-arm64.dmg` |
| guest factory 发布物 | `my-omarchy-guest-<semver>-arm64` |
| OCI 命名空间（如未来发布） | `ghcr.io/superops-team/my-omarchy/*` |
| 默认数据根目录 | `~/Library/Application Support/My Omarchy/VM/v1` |
| Preferences | `team.superops.myomarchy.plist` |
| Cache | `~/Library/Caches/team.superops.myomarchy` |
| Saved State | `team.superops.myomarchy.savedState` |
| QMP/Dispatch 前缀 | `team.superops.myomarchy.*` |
| virtio port 前缀 | `team.superops.myomarchy.*` |
| kernel 参数前缀 | `myomarchy.*` |
| guest 包前缀 | `my-omarchy-*` |
| pacman 本地仓库 | `my-omarchy` |
| guest 数据目录 | `/usr/share/my-omarchy`、`/usr/local/lib/my-omarchy` |
| artifact kind | `my-omarchy-guest-artifacts` |
| Docker 资源前缀 | `my-omarchy-*` |
| Notary profile 默认名 | `my-omarchy` |

以上名称是新产品的 v1 合同。实现不得保留双写或回退到 Try Omarchy 路径。若未来需要修改持久化标识，必须通过 My Omarchy 自身的版本化迁移完成。

## 3. 用户场景

### 场景 1：与旧产品并存

**Given** 用户已经安装 Try Omarchy 并拥有 VM 数据

**When** 用户安装并首次启动 My Omarchy

**Then** My Omarchy 创建自己的数据目录和权限记录，不读取或修改任何 Try Omarchy 文件，两个 App 均可独立启动

### 场景 2：确认发布来源

**Given** 用户从 README、App 关于页或错误页寻找支持入口

**When** 用户打开项目链接

**Then** 所有入口均指向 `superops-team/my-omarchy`，不存在仍被描述为维护入口的 `themartiano/try-omarchy` 链接

### 场景 3：识别独立品牌

**Given** 用户同时看到 Try Omarchy 与 My Omarchy

**When** 用户查看 App 图标、窗口、DMG 或关于页

**Then** 可以仅凭名称、图标和 bundle 信息区分两个产品

## 4. 功能需求

### FR-1：全面身份替换

必须按语义清单替换所有旧标识，覆盖源码、脚本、测试、构建缓存、镜像 metadata、guest 包、文档、DMG、签名标识和运行时协议。禁止仅执行无差别字符串替换；每类标识必须有对应测试。

### FR-2：独立数据边界

My Omarchy 的默认路径解析、清理命令、Factory Reset、外置盘选择和测试夹具只能作用于 My Omarchy 路径。任何生产代码均不得探测 Try Omarchy 默认路径。

### FR-3：旧产品退役声明

README 和发布文档必须包含简短声明：My Omarchy 是由 `superops-team` 维护的独立产品；Try Omarchy 不再由本项目维护。旧地址只能出现在来源说明、许可证或历史归属中，不能作为下载、Issue、支持或更新入口。

### FR-4：品牌资产系统

品牌必须交付原创 Logo symbol、wordmark、App 图标和可复用资产，不得继续使用当前 Omarchy 官方 mark。Logo 采用“独立空间中的个人工作环境”为核心概念，首选设计方向为：

- 以字母 `M` 与“虚拟机窗口/门户边界”进行负空间融合；
- 外轮廓表达稳定的隔离空间，内部路径表达进入自己的 Omarchy；
- 形态简洁，在 16 px 菜单尺寸和 1024 px App 图标尺寸均可辨识；
- 避免与 Basecamp Omarchy 官方 mark、Apple、Docker、UTM、Parallels 等现有标识近似。

视觉性格为精确、克制、原生、可信赖，采用 Dark Developer / Calm System 的交叉方向。建议色板以深石墨色为基础，仅使用一个高识别度冷色主强调色和一个暖色辅助色；最终色值由 Logo 设计阶段确定并通过对比度验证。

必须交付：

1. `SVG` 主标、单色标、反白标和 wordmark。
2. macOS `AppIcon.appiconset` 或等价源资产，覆盖 Apple 要求尺寸。
3. README 标志、DMG 图标、About 面板、空状态和发布页预览资产。
4. 3x3 品牌系统板：Logo、构造、App 图标、数字应用、色板、字体、单色适配和小尺寸测试。
5. 安全区、最小尺寸、禁用示例及颜色 token 文档。

### FR-5：商标和来源合规

发布前必须完成名称与 Logo 的商标近似审查，并在 README/THIRD_PARTY_NOTICES 中清楚区分 My Omarchy 原创代码与上游 Omarchy。不得暗示 My Omarchy 是 Basecamp 官方发行版。

品牌交付必须指定一名品牌 owner 和一名独立合规 reviewer；两者不能由同一人同时签字。审查记录至少包含检索日期、检索地域与数据库、关键词和图形近似范围、已知近似项、差异分析、结论、遗留风险和最终批准人。若团队没有法务资源，产品 owner 必须在记录中明确接受该风险，不得以无责任人的“已审查”勾选项代替。

### FR-6：品牌可测试性

Logo 可辨识性使用固定测试板验收：在浅色、深色和单色背景上分别输出 16、32、128、512、1024 px 位图，不允许手工按尺寸修改图形。16 px 与 32 px 版本必须保持主体轮廓连续、负空间不粘连，并能与同板中的 Try Omarchy、Omarchy 官方 mark 及常见虚拟机产品图标区分。测试板、参与评审者、结果和批准日期作为发布证据保存。

## 5. 实现边界

### 5.1 替换分类

| 分类 | 示例 | 策略 |
|------|------|------|
| 用户品牌 | App 名、窗口、DMG、文档 | 全部替换为 My Omarchy |
| 发布定位 | Releases、Issues、源码链接 | 全部指向 superops-team/my-omarchy |
| macOS 身份 | bundle ID、队列、Preferences | 使用全新 `team.superops.myomarchy` |
| 持久化契约 | 数据根、schema kind、boot ABI | 建立 My Omarchy v1，不兼容旧值 |
| guest ABI | 包、repo、路径、kernel 参数、virtio port | 使用 `my-omarchy`/`myomarchy` 新命名空间 |
| 构建资源 | Docker image/volume、缓存键、产物路径 | 使用 My Omarchy 前缀 |
| 历史与许可证 | copyright、来源链接 | 保留必要归属但明确非维护入口 |

### 5.2 版本来源

版本号必须由 release tag 驱动，并进入 App bundle、guest provenance、DMG 文件名和发布清单。禁止继续只在 `Info.plist` 手工维护孤立版本。

所有公开镜像、factory artifact、checksum、provenance 和容器（若未来需要发布）必须由 `superops-team/my-omarchy` Release 或 `ghcr.io/superops-team/my-omarchy/*` 提供。不得从 Try Omarchy 的 Release、容器仓库或更新地址获取 My Omarchy 运行输入。

## 6. 边界情况

| 场景 | 处理方式 |
|------|----------|
| Try Omarchy 正在运行 | My Omarchy 使用独立进程名、socket 和锁，不干预旧进程 |
| 旧产品占用相同转发端口 | My Omarchy 报告普通本机端口冲突，不尝试控制旧产品 |
| 用户选择旧 VM 目录作为新位置 | 因目录非空且无 My Omarchy marker 而拒绝 |
| 系统中保留旧 TCC 权限 | My Omarchy 以新 bundle ID 单独申请权限 |
| 文档需要说明项目来源 | 可以引用旧仓库，但必须标注历史来源/不再维护 |
| 新 Logo 未通过近似审查 | 不得进入 release 分支，回到概念设计阶段 |

## 7. 涉及文件

- `README.md`、`CONTRIBUTING.md`、`SECURITY.md`、`THIRD_PARTY_NOTICES.md`、`LICENSE`
- `Makefile`、`.github/workflows/*`、`scripts/*`、`tests/*`
- `macos/Info.plist`、`macos/Package.swift`、`macos/Sources/*`、`macos/Tests/*`
- `macos/*.sh`、当前 `macos/OmarchyIcon.svg`（实施后必须重命名为 My Omarchy 目标资产）、App icon 生成流程
- `guest/spec.json`、`guest/scripts/*`、`guest/native-overlay/*`、`guest/factory-overlay/*`、`guest/tests/*`
- 新品牌资产目录与品牌规范文档

## 8. 验收标准

1. 除本 PRD、产品过渡声明、`THIRD_PARTY_NOTICES.md` 的必要来源归属外，对生产源码、构建脚本、测试夹具和用户文档执行 `rg -i 'try[ -]?omarchy|tryomarchy|dev\.tryomarchy|themartiano/try-omarchy'` 无命中；允许文件和允许行必须由独立 allowlist 精确列出，禁止目录级忽略。
2. App bundle ID、签名、Preferences、Cache、Saved State 和默认 VM 路径全部使用 My Omarchy 新身份。
3. Try Omarchy 与 My Omarchy 可并行安装、分别启动并保存独立 VM。
4. My Omarchy 的 Reset 和 `make clean-all` 不访问 Try Omarchy 路径。
5. 所有下载、Issue、源码和安全入口指向 `superops-team/my-omarchy`。
6. guest manifest、包、repo、kernel 参数和 virtio port 均通过新 ABI 合同测试。
7. 新 Logo 使用同一矢量源在固定测试板输出 16、32、128、512、1024 px；16/32 px 主体轮廓连续、负空间不粘连，并具有单色/反白版本。
8. Logo 及 App 图标不再包含旧官方 Omarchy mark；品牌 owner 与独立合规 reviewer 完成包含检索范围、近似项、结论和风险接受人的审查记录。
9. 全新安装、权限申请、Factory Reset、外置路径和清理流程完成真实 Mac 验证。

## 9. 发布阻断条件

出现以下任一情况不得发布：旧维护入口仍可见、bundle ID 或数据路径复用旧值、新产品会读取旧 VM、Logo 仍使用旧 mark、版本与 tag 不一致、品牌资产没有来源和授权记录。
