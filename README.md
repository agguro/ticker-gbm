# Ticker Probability ASM-CUDA Engine

Bare-metal Monte Carlo simulation engine implemented with:
* **x86_64 Assembly** (System V ABI Compliance)
* **NVIDIA PTX** (Parallel Thread Execution)
* **CUDA Driver API** (Zero-dependency hardware orchestration)

The project performs massive-scale, GPU-accelerated probability forecasting on historical financial asset streams using an optimized Geometric Brownian Motion (GBM) model.

The host runtime is written entirely in bare-metal x86_64 assembly, directly managing system resources, memory-mapped I/O, statistical parameter derivation, GPU device execution, and terminal presentation with zero reliance on high-level language runtimes or frameworks.

---

## Overview

The engine estimates the mathematical probability of a financial ticker reaching specific target pricing thresholds over micro and macro horizons.

Historical ticker data is ingested through direct OS-level mappings. The assembly host pre-processes the data on the CPU to calculate current asset values, drift, and daily volatility metrics. These derived values are loaded into a dedicated, quadword-aligned parameter structure passed directly to an independent GPU Monte Carlo kernel.

Each allocated GPU thread executes a self-seeded, high-density stochastic simulation loop. The system aggregates millions of unique future price trajectories to output:
* Expected asset valuation curves.
* Precise probability splits for directional target breaks (S_T > S_0).
* Quantitative verification of downside risk structures.

---

## Architecture

```text
Historical Ticker Binary (.ticker)
        |
        v
x86_64 Assembly Host
        |
        +-- sys_open & sys_fstat (File metrics)
        +-- sys_mmap (Zero-copy binary streaming)
        +-- Parameter Derivation (Drift & Volatility)
        +-- Quadword-Aligned Structure Packing
        +-- CUDA Driver API Orchestration
                |
                v
NVIDIA PTX Monte Carlo Kernel
        |
        +-- Hardware On-Chip Seeding (%clock64)
        +-- Xorshift64 LCG Entropy Loop
        +-- Box-Muller Normal Transformations
        +-- Native 64-Bit Taylor Series exp(x)
        +-- Directional Gate Accumulation
                |
                v
VRAM Global Reduction Buffers
        |
        v
Assembly Presentation Layer (PLT printf)
```

---

## Mathematical Model

The simulation models asset paths via continuous-time Geometric Brownian Motion:

    dS = mu * S * dt + sigma * S * dW

To ensure absolute precision over micro-horizons (such as 1-Day options frames) without encountering 32-bit floating-point truncation errors, the integrated structural evolution step is resolved using native 64-bit IEEE-754 calculations:

    S(t) = S_0 * exp((mu - 0.5 * sigma^2) * t + sigma * Z * sqrt(t))

where the random shock variable is normally distributed: Z ~ N(0,1)

---

## Features

* Pure x86_64 Assembly Host: No C/C++ runtime layer boilerplate. Direct hardware control via raw instructions.
* Pure 64-Bit Precision Evolution: Custom native PTX Taylor Series expansion for exp(x) eliminates lossy 32-bit hardware downcasting traps.
* Zero-Copy File I/O: Maps raw binary financial data structures directly into process memory via sys_mmap.
* Hardware On-Chip Seeding: Blends %clock64 values with Knuth's golden-ratio scrambling constants per thread to guarantee unique, unaligned entropy pathways.
* Deterministic Runtime Alignment: Total System V ABI compliance featuring strict 16-byte stack frame balancing.
* No CUDA Runtime Dependencies: Links natively to libcuda.so via the low-overhead Driver API.

---

## Project Structure

```text
.
├── bin/
│   └── x86_64/
│       └── monte_carlo         # Final compiled native binary
├── build/
│   └── x86_64/
│       ├── monte_carlo.cubin   # Assembled GPU machine code
│       └── monte_carlo.o       # Assembled host object file
├── kernels/
│   └── monte_carlo_kernel.ptx  # Pure 64-bit precision PTX source
├── src/
│   └── x86_64/
│       └── engine/
│           └── monte_carlo.s   # Raw System V host assembly source
├── data/
│   └── PSEC.ticker             # 16-byte aligned historical data blocks
├── Makefile                    # Bare-metal build system configuration
└── README.md                   # System documentation
```

---

## Binary Input Format

Historical ticker files consist of contiguously packed, fixed 16-byte layout records:

```text
Offset    Size (Bytes)    Type       Description
----------------------------------------------------------
0         8               uint64     Unix Epoch Timestamp
8         8               float64    IEEE-754 Closing Price
```

Total file elements are calculated inline via register shifts: records = filesize >> 4

The stream reads the latest price dynamically out of the terminal record index (total_records - 1) to anchor S_0.

---

## Build & Deployment

The compilation pipeline uses native GNU asset handlers and the NVIDIA PTX optimizing assembler (ptxas).

### Compilation Requirements
* Linux x86_64 operating environment
* NVIDIA Display Driver & CUDA Toolkit (libcuda.so)
* Maxwell, Pascal, or newer GPU architecture (sm_61+)
* GNU Assembler (as) and GCC linker tools

### Execution Rules
To clear out binary objects and execute a clean compile pass:

```bash
make clean
make
```

---

## Command Line Usage

Run the compiled executable by specifying the target path, boundary pricing parameters, trajectory counts, and day limits:

```bash
./bin/x86_64/monte_carlo <data.ticker> <target_price> <total_paths> <horizon_days>
```

### Production Examples

**1. Long-Term Macro Trend Optimization (90-Day Forecast)**
```bash
./bin/x86_64/monte_carlo data/PSEC.ticker 0 5000000 90
```

**2. Micro-Horizon Option Boundary Simulation (1-Day Step)**
```bash
./bin/x86_64/monte_carlo data/PSEC.ticker 0 5000000 1
```

---

## Production Terminal Output

```text
------------------------------------------------------------
SIMULATION DIRECTIONAL FORECAST (PSEC.ticker)
Historical Drift    : 0.000150
Historical Vol      : 0.012500
Forecast Horizon    : 1 Days
Simulated Paths     : 4980736

Current Price       : 2.4200
Expected Average    : 2.4204

DIRECTIONAL ANALYSIS:
>> Probability of Net RISE  (S_T > S_0): 50.22%
>> Likelihood of Net DROP   (S_T < S_0): 49.78%
```

---

## ABI Compliance & System Interfaces

The host software strictly honors the System V AMD64 ABI specification layout:
* Mandates explicit 16-byte boundary alignment of %rsp before outbound external calls.
* Maps float statistics across %xmm0 through %xmm7 registers.
* Preserves mandatory nonvolatile registers (%rbx, %rbp, %r12, %r13, %r14, %r15).

File handling and process state boundaries communicate directly with the Linux kernel via architecture-specific interrupts (syscall), bypassing high-level wrappers entirely:

| Syscall | Vector | Target Interface Duty |
| :--- | :--- | :--- |
| sys_open | 0x02 | Obtains read-only file descriptors for ticker files |
| sys_fstat | 0x05 | Inspects target sizing constraints directly from the inode |
| sys_mmap | 0x09 | Maps memory pages directly from disk cache to VRAM allocators |
| sys_exit | 0xE7 | Terminates all current host process tracking spaces cleanly |

---

## Disclaimer

> **CRITICAL MODEL NOTICE:** This engine is a pure numerical simulation instrument. It models hypothetical asset price behavior under strict Geometric Brownian Motion (GBM) assumptions using parameters derived from static historical data.
>
> This simulation is **not** financial advice, a guaranteed oracle of market direction, or a comprehensive representation of real-world exchange mechanics. Results are probabilistic estimates built on simplified stochastic baselines.
>
> Real financial markets feature complex, non-linear anomalies not captured by this model, including structural regime shifts, sudden liquidity collapses, non-Gaussian fat-tail distributions, geopolitical interventions, discontinuous trading gaps, and behavioral human panic cycles. Treat all outputs as theoretical risk boundaries rather than deterministic predictions.

---

## License

This project is licensed under the Apache 2.0 License.
