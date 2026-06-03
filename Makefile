# ==============================================================================
# Multi-Architecture Pipeline: Assembly Host + PTX GPU Orchestrator
# ==============================================================================

# 1. Target Architecture (Defaults to Host x86_64)
ARCH ?= x86_64

# 2. Directory & Path Setup
SRC_DIR     = src/$(ARCH)
BUILD_DIR   = build/$(ARCH)
KERNELS_DIR = kernels
BIN_DIR     = bin/$(ARCH)

# 3. Toolchain & Flag Matrix Configuration
PTXAS    = ptxas
PTXFLAGS = -v -arch=sm_61

ifeq ($(ARCH),x86_64)
    AS      = as
    LD      = ld
    ASFLAGS = --64 -I $(BUILD_DIR)
    LDFLAGS = -dynamic-linker /lib64/ld-linux-x86-64.so.2 -lcuda -lssl -lcrypto -lc -lm
else ifeq ($(ARCH),aarch64)
    AS      = aarch64-linux-gnu-as
    LD      = aarch64-linux-gnu-ld
    ASFLAGS = -I $(BUILD_DIR)
    LDFLAGS = -dynamic-linker /lib/ld-linux-aarch64.so.1 -lcuda -lssl -lcrypto -lc -lm
else
    $(error [ERROR] Unsupported target architecture: $(ARCH))
endif

# 4. Toolchain Validation Layer
CHECK_PTXAS := $(shell which $(PTXAS) 2>/dev/null)
CHECK_AS    := $(shell which $(AS) 2>/dev/null)
CHECK_LD    := $(shell which $(LD) 2>/dev/null)

ifeq ($(CHECK_PTXAS),)
    $(error [ERROR] NVIDIA CUDA Tool 'ptxas' not found in PATH.)
endif
ifeq ($(CHECK_AS),)
    $(error [ERROR] Assembler '$(AS)' not found in PATH.)
endif
ifeq ($(CHECK_LD),)
    $(error [ERROR] Linker '$(LD)' not found in PATH.)
endif

# ==============================================================================
# Explicit Target Definitions
# ==============================================================================

ENGINE_BIN       = $(BIN_DIR)/ticker_gbm
FETCH_TICKER_BIN = $(BIN_DIR)/fetch_ticker

CUBIN = $(BUILD_DIR)/monte_carlo.cubin
PTX   = $(KERNELS_DIR)/monte_carlo_kernel.ptx

# Master target builds exactly what is specified above
all: $(ENGINE_BIN) $(FETCH_TICKER_BIN)

# 5. Build Step 1: Compile PTX to CUBIN
$(CUBIN): $(PTX)
	@mkdir -p $(BUILD_DIR)
	$(PTXAS) $(PTXFLAGS) $< -o $@

# 6. Build Step 2: Assemble and Link Host GPU Engine
$(BUILD_DIR)/monte_carlo.o: $(SRC_DIR)/engine/monte_carlo.s $(CUBIN)
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(ENGINE_BIN): $(BUILD_DIR)/monte_carlo.o
	@mkdir -p $(BIN_DIR)
	$(LD) $< -o $@ $(LDFLAGS)

# 7. Build Step 3: Assemble and Link OpenSSL Ticker Fetcher
$(BUILD_DIR)/fetch_ticker.o: $(SRC_DIR)/tools/fetch_ticker.s
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(FETCH_TICKER_BIN): $(BUILD_DIR)/fetch_ticker.o
	@mkdir -p $(BIN_DIR)
	$(LD) $< -o $@ $(LDFLAGS)

# Clean Workspace
clean:
	rm -rf build bin

.PHONY: all clean
