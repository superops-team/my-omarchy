# My Omarchy Phase 1C Host Identity 实施设计

## 1. 范围

Phase 1C 将 macOS host 层从当前基线身份迁移到 My Omarchy。范围包括 App bundle 名、Swift package/module/executable、bundle identifier、Info.plist 用户可见文案、host-side Preferences/Cache/Saved State、Application Support 默认根、App 内 QEMU executable 名、构建输出、DMG 卷名和 host 文档。

本阶段不修改 guest ABI：guest package/repo/path、kernel 参数、virtio port、guest overlay 文件名、guest manifest、Docker guest builder 名称和 Linux 内部服务仍属于 Phase 1D。若 host 代码中存在 guest-facing token，本阶段只改 host bundle/路径必须使用的值；否则保留到 1D 并在 allowlist 中继续归属 1D。

## 2. 目标身份

目标值来自 `config/product-identity.json`：

| 字段 | 目标值 |
|------|--------|
| App bundle | `My Omarchy.app` |
| Bundle ID | `team.superops.myomarchy` |
| Swift module | `MyOmarchy` |
| Host executable | `my-omarchy` |
| Bundled QEMU executable | `My Omarchy` |
| App icon resource | `MyOmarchy.icns` |
| DMG | `MyOmarchy.dmg` |
| Notary profile default | `my-omarchy` |
| Preferences | `team.superops.myomarchy.plist` |
| Cache directory | `team.superops.myomarchy` |
| Saved state | `team.superops.myomarchy.savedState` |
| Default VM root | `~/Library/Application Support/My Omarchy/VM/v1` |

## 3. Required behavior

1. `make app` installs `dist/app.noindex/My Omarchy.app`.
2. `macos/build-app.sh` builds Swift release executable `my-omarchy`, packages `MyOmarchy.icns`, signs the app and bundled QEMU with `team.superops.myomarchy`, and names the bundled QEMU executable `My Omarchy`.
3. `Info.plist` exposes My Omarchy display name, executable, bundle ID, icon file and privacy strings.
4. Swift code imports module `MyOmarchy` in tests and source paths use `Sources/MyOmarchy`.
5. The default persistent VM root is `Application Support/My Omarchy/VM/v1`.
6. Storage tests continue to verify that old predecessor roots are not recreated or deleted.
7. `make clean-all` must not delete predecessor product data. It may clean My Omarchy paths and My Omarchy temporary/build resources only.
8. README, macOS README, releasing docs and architecture docs describe My Omarchy host outputs. Explicit historical/source references remain allowed only where needed.
9. `make verify-release-identity` no longer reports ownerPhase `1C`.

## 4. TDD sequence

1. Add host identity contract tests around `Info.plist`, `macos/Package.swift`, `Makefile`, `macos/build-app.sh`, storage script defaults and `make help`.
2. Rename Swift package/module/executable paths and update all `@testable import` statements.
3. Replace host display names, executable names, bundle identifiers, icon resource names, DMG names, signing identifiers and cache/saved-state paths.
4. Update Swift code and shell tests that assert host names or default Application Support paths.
5. Keep guest ABI tokens on the Phase 1D allowlist and remove all Phase 1C allowlist entries.
6. Run host-focused tests and identity gates.

## 5. Verification

Required before commit:

1. `python3 -m unittest -v tests/test-product-identity.py tests/test-build-cache.py tests/test-pack-app-icon.py`
2. `macos/Tests/macos-compatibility.test.sh`
3. `macos/Tests/runtime-relocation.test.sh`
4. `cd macos && swift build --disable-sandbox -c release`
5. `make verify-identity`
6. `make verify-release-identity` must still fail only for Phase 1D owner entries.
7. `git diff --check`

If full `swift test` remains blocked by the machine's missing Swift `Testing` module, that remains the Phase 0 environment blocker; changed tests must still be statically updated and buildable once that module is available.

## 6. Completion definition

Phase 1C is complete when host identity output, host runtime names, host data roots, host docs and host tests all use My Omarchy; `ownerPhase=1C` disappears from `config/legacy-identity-allowlist.json`; no Phase 1D guest ABI names are silently changed; and existing user guest/Fcitx5/keyboard work remains outside the branch.
