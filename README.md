# MIPS CPU with AXI and caches / 带 AXI 与缓存的 MIPS CPU

这个仓库整理了 `myCPU` 目录中的 Verilog RTL。顶层模块 `mycpu_top` 面向 `func_test_v0.01/soc_axi_func` 的 AXI 接口，连接五级流水线 CPU、指令/数据缓存桥和 AXI 主设备。

This repository contains the Verilog RTL from the `myCPU` directory. The `mycpu_top` module targets the AXI interface used by `func_test_v0.01/soc_axi_func` and connects a five-stage pipeline core, instruction/data cache bridge, and AXI master.

## 架构 / Architecture

```text
                  +------------------+
                  |  pipeline_core   |
                  | IF ID EX MEM WB  |
                  +--------+---------+
                           |
                  +--------+---------+
                  | cached_axi_bridge|
                  | 2 KiB I / 2 KiB D|
                  +--------+---------+
                           |
                  +--------+---------+
                  |    axi_master    |
                  +--------+---------+
                           |
                        AXI bus
```

- 五级顺序流水线；译码、执行、访存、寄存器堆、CP0 和迭代除法器各有独立模块。
- 2 KiB 直接映射指令缓存和 2 KiB 直接映射数据缓存，每行四个 32 位字。数据缓存采用写直达、不写分配策略。
- 顶层输出写回调试信号，方便与外部测试环境连接。

- Five-stage in-order pipeline, with separate decode, execute, memory access, register file, CP0, and iterative divider modules.
- 2 KiB direct-mapped instruction and data caches, with four 32-bit words per line. The data cache is write-through and no-write-allocate.
- Writeback debug signals are exposed at the top level for external test environments.

## 文件 / Files

| File | Purpose |
| --- | --- |
| `rtl/mycpu_top.v` | Top-level AXI and debug interface |
| `rtl/pipeline_core.v` | Five-stage pipeline and control |
| `rtl/cached_axi_bridge.v` | Instruction/data caches and request bridge |
| `rtl/axi_master.v` | AXI transaction controller |
| `rtl/decode_unit.v` | Instruction decode |
| `rtl/execute_unit.v` | ALU and arithmetic execution |
| `rtl/memory_access_unit.v` | Load/store formatting and alignment |
| `rtl/cp0_regs.v` | CP0 registers and exception state |
| `rtl/iterative_divider.v` | Iterative division |
| `rtl/regfile.v` | General-purpose register file |
| `rtl/mips_defs.vh` | Shared MIPS constants |

## 使用 / Usage

将 `rtl` 下的所有 `.v` 文件加入 Verilog 工程，并把 `rtl` 加入 include 搜索路径；综合或仿真的顶层选择 `mycpu_top`。外部平台需要提供 AXI 从设备、时钟、复位和测试程序。

Add all `.v` files under `rtl` to a Verilog project and add `rtl` to the include search path. Select `mycpu_top` as the top module. An external platform must supply the AXI slave, clock, reset, and test program.

本仓库只包含指定 `myCPU` 目录中的 RTL。原工程的测试平台、Vivado 工程和生成文件没有纳入；目前未在此独立仓库中运行完整仿真。因此这里不声明性能或功能测试通过。

This repository contains only the RTL from the specified `myCPU` directory. The surrounding testbench, Vivado project, and generated files are not included. Full simulation has not been run in this standalone repository, so no performance or functional test result is claimed here.

## 许可 / License

目前未指定开源许可证。公开可见并不自动授予复制、修改或再发布的权利。若后续确定授权方式，可再添加 `LICENSE` 文件。

No open-source license is specified yet. Public visibility does not itself grant permission to copy, modify, or redistribute the code. A `LICENSE` file can be added when the intended terms are decided.
