# My Omarchy Phase 1B 品牌资产实施设计

## 1. 范围

Phase 1B 只完成 My Omarchy 的原创品牌资产、App 图标、品牌来源记录、商标近似自查和品牌类旧身份清零。它不修改 macOS bundle ID、App bundle 名、Swift module、可执行文件、数据目录、guest ABI、kernel 参数、virtio port、Docker 资源或发布产物命名；这些分别属于 Phase 1C 和 Phase 1D。

本阶段选定的视觉方向为 **Portal M**。该方向来自 Phase 1B 视觉 companion 中的 A 方案：稳定的虚拟机边界、字母 `M` 和进入个人 Omarchy 工作环境的负空间入口。

## 2. 品牌策略

My Omarchy 是 macOS 上的轻量级个人 Omarchy VM。品牌应表达三个信号：

1. 个人所有权：这是用户自己的 Omarchy 环境，不是旧产品的延续。
2. 隔离边界：VM 是稳定、可预期、可恢复的工作空间。
3. 进入路径：从 Mac 进入 Linux 桌面应感觉直接、清晰、受控。

视觉上避免继续使用官方 Omarchy mark、旧 Try Omarchy 图形、通用 Linux 吉祥物、复杂徽章和营销型插画。Logo 必须在 16px、32px、64px、128px、512px 和 1024px 下保持可识别，并能作为 README 头图、AppIcon、DMG 图标和品牌文档的共同源。

## 3. Portal M 设计规范

### 3.1 Symbol

Logo symbol 使用一个深色圆角方形作为外部 VM 边界，内部是几何化 `M`。`M` 的中部负空间形成向内的门户，表达“进入自己的 Omarchy”。外框与内部字形必须由简单路径构成，避免依赖滤镜、位图纹理、外部字体或不可复现效果。

建议几何特征：

- 1024x1024 SVG viewBox。
- 外部 tile 保留 macOS 图标安全区，圆角不超过图标宽度的 24%。
- `M` 主体采用白灰色实心路径，保证暗色和浅色背景上均可读。
- 门户或进入路径采用单一强调色，不超过两个辅助色。
- 小尺寸导出时不得依赖细线、半透明阴影或细碎分割。

### 3.2 Palette

Phase 1B 固定最小品牌色：

| Token | Value | 用途 |
|------|-------|------|
| `my-omarchy-ink` | `#151A1D` | AppIcon 深色背景、品牌底色 |
| `my-omarchy-paper` | `#EFF6F3` | `M` 主体、浅色文字 |
| `my-omarchy-portal` | `#D8F275` | 边界、主要强调 |
| `my-omarchy-signal` | `#2AD6B5` | 门户负空间或进入路径 |

这些色值用于品牌资产，不要求 Phase 1B 改动 App UI 配色。任何后续 UI 主题化应单独设计。

### 3.3 Wordmark

Wordmark 文本为 `My Omarchy`。Phase 1B 不引入自定义字体文件；品牌文档和 SVG 中如需展示 wordmark，使用系统字体说明或将字形转换为可审查路径。AppIcon 本身只使用 symbol，不把文字塞入图标。

## 4. 交付物

本阶段新增或更新以下文件：

- 更新 `macos/OmarchyIcon.svg` 为原创 Portal M 图标源。
- 新增 `docs/brand/my-omarchy-brand.md`，记录品牌概念、色值、使用边界、来源声明和商标近似自查。
- 新增 `docs/brand/portal-m-construction.svg`，作为可审查的几何构造说明。
- 新增 `docs/brand/my-omarchy-brand-board.svg`，展示 symbol、wordmark、小尺寸预览、色板和应用示例。
- 扩展 `tests/test-pack-app-icon.py` 或新增品牌资产测试，验证 SVG 不再包含旧官方 mark 来源、旧标题、旧仓库链接或 `Try Omarchy` 文案，并包含 Portal M 所需 title/desc。
- 更新 `README.md` 的图标 alt 文案，不再称当前图标为 legacy pending replacement。
- 更新 `config/legacy-identity-allowlist.json`，清除 ownerPhase=`1B` 的品牌类旧身份条目。

不新增提交大型生成 PNG/ICNS，除非现有构建流程要求。正式 AppIcon 继续由 `macos/build-app.sh` 从 SVG 源生成。

## 5. 门禁

本阶段必须通过：

1. `python3 -m unittest -v tests/test-pack-app-icon.py tests/test-product-identity.py`
2. `make verify-identity`
3. `make verify-release-identity` 仍应失败，但 1B 剩余项必须为 0；只允许继续报告 1C/1D。
4. `git diff --check`

若当前机器仍缺少 Swift `Testing` module，完整 `make test` 可以保留 Phase 0 已记录阻断，但本阶段必须证明新品牌测试、identity baseline 和 release 汇总行为通过。

## 6. 商标与来源自查

Phase 1B 的商标近似自查是工程侧初筛，不替代法律审查。记录必须覆盖：

- 未使用官方 Omarchy mark、旧 Try Omarchy 图标或第三方图形资产。
- Logo 由本仓库 SVG 路径构成，可在源文件中审查。
- 视觉核心与旧官方 mark 不同：Portal M 是字母/边界/入口组合，不是旧官方几何迷宫形。
- README 或品牌文档保留 My Omarchy 与上游 Omarchy 的关系说明，避免暗示官方背书。

## 7. 完成定义

Phase 1B 完成时：

1. `macos/OmarchyIcon.svg` 为原创 Portal M 图标，title/desc 均为 My Omarchy。
2. README 头部图标和 alt 文案使用新品牌资产。
3. 品牌文档、构造图和品牌板存在并可审查。
4. `make verify-identity` 通过，且 1B allowlist 项全部清零。
5. `make verify-release-identity` 的 ownerPhase 汇总不再包含 1B。
6. 未修改 Phase 1C/1D 所属技术命名、host 存储、guest ABI 或用户未提交 guest 输入法/键盘改动。
