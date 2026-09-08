# My Omarchy Phase 0 基线

## 1. 采集范围

- 采集日期：2026-09-08（Asia/Shanghai）
- 基线提交：`51a1f419b5764a51d43aef6337b175452e5fec2a`
- 平台：macOS 26.5.1，Apple Silicon arm64
- Swift：Apple Swift 6.3.2（swiftlang-6.3.2.1.108）
- Xcode：未安装或未选择完整 Xcode；active developer directory 为 Command Line Tools
- Docker：29.6.2
- 系统 PATH 中的 QEMU：未安装；项目应使用后续构建并封装的 pinned runtime

本记录来自隔离 worktree，不包含用户名、HOME 绝对路径、签名身份或凭据。它记录改名前的真实状态，不代表 My Omarchy release qualification 已通过。

## 2. Toolchain doctor

执行：

```sh
make doctor
```

初始结果：失败，稳定错误为：

```text
error: Swift toolchain cannot compile the Testing module
```

后续修正：macOS Swift package 显式 pin `swift-testing` 0.12.0，`make doctor`
改为构建仓库的 SwiftPM 测试入口，而不是脱离包依赖直接 `swiftc
-typecheck import Testing`。这使 Command Line Tools 环境也能使用仓库锁定的
测试模块，并继续在全量测试前 fail closed。

## 3. 测试基线

执行：

```sh
make test
```

| 测试组 | 结果 | 证据摘要 |
|--------|------|----------|
| `tests/test-build-cache.py` | 通过 | 9 tests passed |
| `tests/test-pack-app-icon.py` | 通过 | 6 tests passed |
| `guest/test` Python suite | 通过 | 64 tests passed |
| guest contract verification | 通过 | `native guest contract verified` |
| macOS compatibility | 通过 | `macos compatibility tests passed` |
| runtime relocation | 通过 | `runtime relocation tests passed` |
| Swift product compilation | 通过 | `my-omarchy` 完成 link |
| Swift test target | 已修复 | `swift-testing` 0.12.0；202 tests passed |
| QEMU port/power/storage shell tests | 通过 | 完整 `make test` 已继续覆盖 |

该失败曾是环境工具链阻断，不是产品回归；当前修复路径是把 Swift Testing
作为测试依赖随仓库解析并锁定。发布前仍必须重新运行完整 `make test`。

## 4. 制品与运行基线

隔离 worktree 中没有 `dist/` 制品，系统 PATH 中也没有 `qemu-system-aarch64`。本阶段未触发 guest/runtime 构建、签名、公证、App 启动或 VM 数据访问，因此下列项目均为“未采集”：

- App bundle 和 DMG digest；
- guest factory 与 runtime digest；
- VM 冷启动时间和 graphical-ready 时间；
- QEMU 空闲 CPU；
- 宿主 memory pressure；
- raw disk logical/allocated bytes；
- 真实设备首次启动、输入、音视频、睡眠唤醒和外置盘 E2E。

这些项目必须在具备完整 Xcode 和项目构建产物的真实 Apple Silicon 测试机补采。Phase 3 才会根据固定 benchmark schema 冻结性能阈值，本记录不能直接充当发布性能基线。

## 5. Phase 0 结论

1. 非 Swift 测试与 Swift 产品编译链路在本机通过。
2. Swift `Testing` module 阻断已通过仓库级 `swift-testing` 依赖修复。
3. 新 doctor 已能在全量测试前验证 SwiftPM 测试入口可构建。
4. 当前没有可用于发布、性能比较或真实 VM E2E 的可信制品。
5. Phase 1A 可以继续建立设计时 identity contract 和扫描门禁；后续发布退出门禁仍要求在 release candidate 上重跑全部测试和真实设备验证。

## 7. Phase 1A identity inventory

`make verify-identity` 已对当前受版本控制文本建立精确基线：248 个
path/pattern 条目，共 651 次旧身份命中。严格发布模式当前按迁移 owner 汇总为：

| Owner phase | 条目 | 命中次数 |
|-------------|-----:|---------:|
| 1B | 8 | 36 |
| 1C | 140 | 333 |
| 1D | 81 | 216 |

另有 19 个永久条目、66 次命中，仅用于历史归属和扫描器负向测试夹具。
因此 `make verify-release-identity` 在 Phase 1A 预期失败；该结果是后续
1B/1C/1D 的清零队列，不代表当前产品可发布。
