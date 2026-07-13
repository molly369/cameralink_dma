# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库中工作时提供指导。

## 项目概述

基于 Vivado 2018.3 的 **CameraLink Full → AXI VDMA → DDR** 视频采集管道项目，目标平台为 **Xilinx Zynq UltraScale+ MPSoC**（`xczu7eg-ffvc1156-2-i`）。PL 端接收模拟的 CameraLink Full 数据（3×28-bit 端口 = 8 tap × 8 bit），将其重组为 64-bit AXI4-Stream，再通过 DMA 将帧数据传输到 DDR 内存。PS 端（ARM Cortex-A53 裸机程序）负责配置管道并监控帧数据。

## 构建命令

### FPGA 比特流（Vivado）

在 Vivado 2018.3 GUI 中打开项目，或使用 Tcl 命令：

```tcl
# 打开工程
open_project cemaralink_dma.xpr

# 运行综合 + 实现 + 生成比特流
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 导出硬件（含比特流）供 SDK 使用
file mkdir cemaralink_dma.sdk
write_hw_platform -fixed -force -file cemaralink_dma_wrapper.hdf
```

### PS 软件（Xilinx SDK 2018.3）

SDK 工作空间位于 `cemaralink_dma.sdk/`。应用工程为 `cameralink_vdma_test`，目标 CPU 为 `psu_cortexa53_0`。

可通过 SDK GUI 或命令行构建：
```bash
# 先构建 BSP，再构建应用
xsdk -batch -source build.tcl   # （如有构建脚本）
```

主应用源码文件为 [vdmatest.c](cemaralink_dma.sdk/cameralink_vdma_test/src/vdmatest.c)。

### 仿真

`sim_1` 中没有工程级 testbench。但自定义的 cameralink_decoder IP（位于 `../ip_repo/cameralink_decoder_axi_1.0/`）包含一个基于 AXI BFM 的示例 testbench：
```
../ip_repo/cameralink_decoder_axi_1.0/example_designs/bfm_design/cameralink_decoder_axi_v1_0_tb.sv
```

Block Design 中还包含一个仿真源集 `cemeralink_dma.bd → cameralink_full_sim_source`，内含用于行为仿真的 FIFO Generator。在 Vivado 中运行：
```tcl
launch_simulation
```

## 架构

### Block Design（`cemeralink_dma`）

BD 文件为 [cemeralink_dma.bd](cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/cemeralink_dma.bd)（JSON 格式）。顶层 wrapper：[cemeralink_dma_wrapper.v](cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/hdl/cemeralink_dma_wrapper.v)。

**数据通路：**
```
datasource (测试图像源)              PS AXI (HPM0_FPD @ ~97 MHz)
    | 3×28-bit @ 80 MHz                      |
    v                                         v
cameralink_decoder (像素重组)         ps8_0_axi_periph (1→3 互联)
    | 64-bit AXI4-Stream                       |
    v                                         +→ cameralink_decoder AXI4-Lite (0xA000_0000)
axi_vdma (仅 S2MM)                            +→ axi_vdma AXI4-Lite (0xA000_1000)
    | M_AXI_S2MM                               +→ (未使用的 M02)
    v
axi_smc (SmartConnect)
    |
    v
PS HP0_FPD → DDR
```

### 关键组件

| 组件 | IP 核 | 功能 |
|-----------|-----|------|
| `zynq_ultra_ps_e_0` | Zynq US+ PS v3.2 | Cortex-A53，DDR4（8Gb，16-bit，2400P），UART0（MIO 34-35，115200），pl_clk0 输出 |
| `clk_wiz_0` | Clocking Wizard v6.0 | MMCM：97 MHz pl_clk0 → 80 MHz cam_clk_out，供给 datasource |
| `datasource_0` | 自定义 RTL（`module_ref:datasource:1.0`） | 测试图像源：1280×1024 帧，8 个自增 tap，CameraLink Full 格式 |
| `cameralink_decoder_a_0` | 自定义用户 IP（`user:cameralink_decoder_axi:1.0`） | 将 3×28 位重组为 64-bit AXI4-Stream，含异步 FIFO 跨时钟域，AXI4-Lite 配置接口 |
| `axi_vdma_0` | AXI VDMA v6.3 | 仅 S2MM 通道，3 帧缓冲，循环模式，通过 HP0 写入 DDR |
| `axi_smc` | SmartConnect v1.0 | 1 对 1 AXI MM 桥接（VDMA → PS HP0） |
| `ps8_0_axi_periph` | AXI Interconnect v2.1 | 1 对 3 互联，含数据位宽（128→32）与协议（AXI4→AXI4Lite）转换器 |

### 时钟域

- **PS 时钟域**（~97 MHz `pl_clk0`）：PS AXI 主设备、AXI 互联、VDMA、decoder AXI-Lite 接口
- **Camera 时钟域**（80 MHz `clk_wiz_0/clk_out1`）：datasource、decoder 的 cam_clk_in
- 跨时钟域通过 `cameralink_decoder` 内部的异步 FIFO 实现
- 异步时钟组约束文件：[timing_cdc.xdc](cemaralink_dma.srcs/constrs_1/new/timing_cdc.xdc)

### 地址映射（PS AXI GP0）

| 外设 | 基地址 | 大小 |
|-----------|-------------|------|
| cameralink_decoder_a_0 (S00_AXI) | `0x00A000_0000` | 4K |
| axi_vdma_0 (S_AXI_LITE) | `0x00A000_1000` | 4K |

### 自定义 HDL 源文件

- [datasource.v](cemaralink_dma.srcs/sources_1/new/datasource.v) — CameraLink Full 测试图像发生器。参数：H=1024，W=160（1280/8 拍每行）。输出 28-bit X/Y/Z 端口，FVAL/LVAL/DVAL 嵌入在位[25:24,26]。8 个计数器 tap 每周期自增。
- [cameralink_decoder.v](cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/ipshared/5cf6/src/cameralink_decoder.v) — 核心解码器：将 3×28-bit CameraLink 端口重组为 8 tap → 64-bit AXI4-Stream 数据。使用 `fifo_generator_0` 实现 cam_clk → axis_clk 跨时钟域。生成 tuser（帧起始）和 tlast（行结束）。状态寄存器：bit0=fifo_full，bit1=tvalid，bit2=溢出错误（粘滞）。
- [cameralink_decoder_axi_v1_0.v](cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/ipshared/5cf6/hdl/cameralink_decoder_axi_v1_0.v) — 顶层 AXI wrapper，例化解码器核心 + AXI4-Lite 从设备。
- [cameralink_decoder_axi_v1_0_S00_AXI.v](cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/ipshared/5cf6/hdl/cameralink_decoder_axi_v1_0_S00_AXI.v) — AXI4-Lite 寄存器文件（4 个寄存器）：

| 偏移 | 名称 | 位域 | 读写 | 描述 |
|--------|------|------|-----|-------------|
| 0x00 | CONTROL | [0] cfg_enable，[1] cfg_soft_reset_n，[2] cfg_clear_status | R/W | 使能与复位 |
| 0x04 | STATUS | [0] fifo_full，[1] tvalid，[2] overflow_error | RO | 解码器状态 |
| 0x08 | WIDTH | [15:0] | R/W | 帧宽度（默认 1280） |
| 0x0C | HEIGHT | [15:0] | R/W | 帧高度（默认 1024） |

### PS 软件（`cameralink_vdma_test`）

Cortex-A53 裸机应用，基于 Xilinx standalone BSP v6.8 构建。

- [vdmatest.c](cemaralink_dma.sdk/cameralink_vdma_test/src/vdmatest.c) — 主测试程序：初始化解码器，配置 VDMA S2MM 为循环模式（3 个缓冲区，基址 `0x10000000`），使能采集，然后周期性打印状态和帧数据。
- [lscript.ld](cemaralink_dma.sdk/cameralink_vdma_test/src/lscript.ld) — 链接脚本：代码/数据位于 DDR `0x0`（大小 0x7FF00000），OCM 位于 `0xFFFC0000`。
- 帧缓冲位于 `0x10000000`（3× 1,310,720 字节）。测试中禁用了 DCache，以避免 VDMA 写入 DDR 时与 CPU 缓存的一致性问题。
- 使用的主要驱动：`xaxivdma`（v6.6）、GPIO、UART、GIC、standalone OS。

### 图像格式

- 分辨率：1280×1024
- 每 AXI beat 8 像素（64-bit 数据总线）
- 每像素 1 字节（灰度）
- CameraLink Full：8 tap → 3 端口（X：tap 1-3，Y：tap 4-6，Z：tap 7-8），每端口 28 bit

## 文件组织

| 目录 | 用途 |
|-----------|---------|
| `cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/` | Block Design（BD + 生成的 wrapper） |
| `cemaralink_dma.srcs/sources_1/bd/cemeralink_dma/ipshared/5cf6/` | 自定义 cameralink_decoder IP 源码 |
| `cemaralink_dma.srcs/sources_1/new/` | 用户 HDL（datasource.v） |
| `cemaralink_dma.srcs/sources_1/bd/mref/datasource/` | datasource IP 组件定义 |
| `cemaralink_dma.srcs/constrs_1/new/` | XDC 约束文件 |
| `cemaralink_dma.sdk/cameralink_vdma_test/src/` | PS 应用源码 |
| `cemaralink_dma.sdk/cameralink_vdma_test_bsp/` | 板级支持包（BSP） |
| `cemaralink_dma.sdk/cemeralink_dma_wrapper_hw_platform_0/` | 硬件平台（PS 初始化代码） |
| `cemaralink_dma.runs/` | 综合/实现运行输出 |
| `cemaralink_dma.cache/` | Vivado IP 缓存 |

## 重要说明

- **无外部 I/O 端口**：顶层 wrapper 没有任何端口——这是一个纯内部的概念验证设计。`datasource` 在内部生成测试图像；实际部署时需替换为真正的 CameraLink 接收器 I/O 引脚。
- **Vivado 版本**：2018.3——版本较旧；在新版本中打开可能需要升级 IP。cameralink_decoder_axi IP 在工程搭建期间经历了 6 次版本升级（Rev 6→11），详见 `ip_upgrade.log`。
- **自定义 IP 仓库**：cameralink_decoder_axi IP 源码位于工程目录外的 `../ip_repo/cameralink_decoder_axi_1.0/`（相对于 XPR 文件的路径）。
- **VDMA 仅为 S2MM 模式**（无 MM2S 读通道）——这是一个纯采集管道。
- **VDMA 配置**：循环缓冲模式，3 个帧缓冲，无帧同步，无 GenLock。
- `datasource` 模块在 `negedge clk` 上驱动 cam_port 数据——decoder 在 `posedge cam_clk_in` 上采样，提供半个周期的建立时间。
- PS 测试程序中有意禁用了 DCache，因为 VDMA 写入 DDR 会绕过 CPU 缓存。
- `cameralink_decoder` 的溢出错误（status bit 2）是粘滞的——一旦触发就锁存，必须通过 `cfg_clear_status` 清除。
- [timing_cdc.xdc](cemaralink_dma.srcs/constrs_1/new/timing_cdc.xdc) 中的异步时钟约束将 80 MHz camera 时钟与 ~97 MHz PS 时钟声明为 false path。
