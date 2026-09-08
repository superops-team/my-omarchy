# My Omarchy 轻量虚拟机运行时设计文档

## 1. 概述

### 1.1 问题

当前 VM 固定分配 4 GiB RAM，并按宿主 CPU 数最多提供 8 vCPU；virtio-balloon 设备存在但没有宿主内存压力调节策略。持久盘以稀疏 raw 文件扩展到 24 GiB，但 QEMU block 后端和 guest 未形成 discard/fstrim 回收合同。视频解码仍为 CPU-only，也没有以启动时间、空闲 CPU、内存、功耗和视频体验定义“轻量”。

### 1.2 目标

1. 根据 Apple Silicon Mac 的物理资源选择安全、可预测的默认 CPU/RAM。
2. 让 guest 删除的数据能够被 APFS 宿主实际回收。
3. 建立轻量运行时性能预算和自动回归基线。
4. 保持桌面、浏览器、开发工具和 Omarchy 更新的可用性。

### 1.3 非目标

- 本阶段不承诺 GPU 视频硬解码。
- 不提供任意 QEMU 参数编辑器。
- 不支持 Intel Mac 或非 Apple Silicon 虚拟化。
- 不通过删除 Omarchy 核心桌面能力来制造更低指标。

## 2. 用户场景

### 场景 1：8 GiB Mac 日常启动

**Given** 用户在满足最低条件的 8 GiB Apple Silicon Mac 上启动 My Omarchy

**When** VM 创建默认配置

**Then** My Omarchy 不固定占用 4 GiB，不使宿主进入持续内存压力，同时桌面和基础浏览器可正常使用

### 场景 2：删除 guest 大文件

**Given** VM 曾写入数 GiB 文件并导致 APFS 实际占用增加

**When** 用户删除文件且定期 trim 完成

**Then** 宿主 raw 文件的 allocated bytes 明显下降，而 VM 仍可启动且文件系统一致

### 场景 3：性能退化被发布门禁发现

**Given** QEMU、kernel、VirGL 或 guest 包发生更新

**When** 发布候选运行性能基准

**Then** 空闲 CPU、内存、功耗、启动和 1080p30 视频指标与基线比较，超预算时阻断发布

## 3. 功能需求

### FR-1：资源策略

默认资源档由宿主物理内存和逻辑 CPU 自动选择：

| 宿主资源 | 默认 vCPU | guest RAM |
|----------|-----------|-----------|
| 8 GiB 内存 | 4 | 2560 MiB |
| 16 GiB 内存 | 4 | 4096 MiB |
| 24 GiB 及以上 | 6 | 4096 MiB |

宿主少于 4 个逻辑 CPU 或少于 8 GiB 内存时拒绝启动并说明要求。默认不得使用 8 vCPU。资源策略必须集中在一个版本化模型中，并由 launcher 和测试共同消费，禁止 shell 与 Swift 各自复制阈值。

### FR-2：用户配置档

首版仅提供“自动（推荐）”和“兼容/低资源”两个档位。低资源档为 4 vCPU、2048 MiB，仅用于 8 GiB Mac 或故障恢复，并明确可能降低浏览器和更新性能。高级自定义参数不进入首版 UI。

### FR-3：内存回收

guest 保留 zram。若使用 virtio-balloon，必须通过 QMP 与 macOS memory pressure 事件形成受测试的收缩/恢复策略，设置最低 guest RAM、迟滞和速率限制；在该策略完成前不得宣称支持动态内存回收。若实测收益不足，可在 v1 移除 balloon，依靠静态档位。

### FR-4：磁盘 discard 合同

QEMU block 后端必须支持 guest discard 映射到 APFS sparse file hole punching。实现需显式声明 `discard=unmap`，是否启用 `detect-zeroes=unmap` 由数据完整性和性能测试决定。guest 必须启用 `fstrim.timer`，并允许用户从诊断界面手动触发安全 trim。

### FR-5：磁盘占用展示

启动菜单显示 VM 逻辑容量与宿主实际占用，避免把 24 GiB logical size 描述为已经使用。空间不足时同时报告宿主卷可用空间和 guest 根文件系统可用空间。

### FR-6：性能预算

每个 release candidate 必须采集以下指标：

| 指标 | v1 预算 |
|------|---------|
| 已进入桌面后的 QEMU 空闲 CPU | 5 分钟中位数不高于 20% 单核，且不高于已批准基线 1.25 倍 |
| 8 GiB Mac 宿主 memory pressure | 10 分钟空闲/轻浏览期间不得进入持续红色压力 |
| 冷启动到可交互桌面 | 同机型不高于基线 1.25 倍 |
| 睡眠时 VM CPU | 暂停后接近 0 |
| 1080p30 视频 | 记录 dropped frames、QEMU CPU、整机能耗和音画同步；不得比基线退化超过 20% |

绝对功耗受机型影响，只按同设备、同系统、同测试内容比较。建立三次运行的中位数，首次基线需人工批准。

### FR-7：CPU-only 视频说明

在硬解码实现并通过验证前，README 和 Release notes 必须保持明确限制，不得把“Metal 渲染”误写为“视频硬件解码”。

## 4. 实现方案

### 4.1 资源模型

Swift launcher 采集 `ProcessInfo.physicalMemory` 与 active processor count，资源策略模块返回版本化 `VMResourceProfile`，再通过显式环境变量传给 shell launcher。shell 对范围进行二次验证，不能自行重新选择。最终有效值写入启动日志和 release evidence。

### 4.2 discard 路径

数据流为：guest ext4 discard → virtio-blk → QEMU raw block backend → APFS sparse file。测试必须同时观察 guest `fstrim` 返回、raw 文件 logical bytes 和 macOS `stat` allocated blocks；只看到 guest 命令成功不算验收。

### 4.3 性能测试

提供固定的空闲、轻浏览、1080p30 和 sleep/wake 场景。脚本只负责采样，结果写入 JSON；阈值判断使用同机型已批准基线。测试内容、浏览器版本、分辨率和电源状态必须固定。

## 5. 边界情况

| 场景 | 处理方式 |
|------|----------|
| 无法读取宿主资源 | 启动失败，不回退到高资源默认值 |
| trim 不被底层支持 | 记录为不支持并阻断稳定发布 |
| 外置 APFS 卷空间很低 | 启动前阻断，不依赖 guest 内部错误 |
| memory pressure 高频抖动 | balloon 策略使用迟滞与冷却时间 |
| 用户运行重负载 | 性能预算只在受控 benchmark 环境判定 |
| 视频硬解尚未完成 | 保留限制和量化基线，不伪造能力 |

## 6. 涉及文件

- `macos/run-qemu-gpu.sh`
- `macos/Sources/OmarchyVMHelper/*` 和对应测试
- `guest/spec.json`、systemd overlay、guest contract tests
- 存储集成测试和性能测试脚本
- README、release evidence 和支持矩阵

## 7. 验收标准

1. 8/16/24 GiB 宿主分别选择表中资源值，异常输入被拒绝。
2. 默认任何机型均不再分配 8 vCPU。
3. 在 guest 写入并删除至少 4 GiB 可压缩和不可压缩测试数据后，trim 使宿主 allocated bytes 回收至少 80% 的对应新增占用。
4. trim 后执行 guest 文件系统检查、重启与数据 hash 校验。
5. VM UI 同时显示逻辑容量和实际宿主占用。
6. 支持矩阵设备通过空闲 CPU、memory pressure、启动和 sleep 预算。
7. 1080p30 性能报告进入 release evidence，CPU-only 限制在文档中保持醒目。
8. resource profile、discard 和 fstrim 均有确定性合同测试与真实机验证。
