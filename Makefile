# ==============================================================================
# ASM-LINUX-FRAMEWORK: UNIVERSELE ORCHESTRATOR (Project Root)
# ==============================================================================

# 1. TOOLCHAIN DETECTION & VALIDATION
PTXAS    := $(shell which ptxas 2>/dev/null)
NVDISASM := $(shell which nvdisasm 2>/dev/null)

ifeq ($(PTXAS),)
    $(error CRITICAL: 'ptxas' not found in $$PATH. Please install nvidia-cuda-toolkit!)
endif

ifeq ($(NVDISASM),)
    $(error CRITICAL: 'nvdisasm' not found in $$PATH. Please install nvidia-cuda-toolkit!)
endif

# 2. LAUNCH CONTEXT DETECTIE
# Als deze repo standalone wordt gebouwd, is DIT de launch root.
# Als hij via asm-multiarch komt, hergebruiken we die reeds geëxporteerde root.
ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR))/
endif

# 3. ARCHITECTUUR LAGEN DEFINITIE
# We dwingen de twee vaste hoofdlagen af. Dit elimineert elke kans op zelf-recursie.
SUBDIRS      := kernels x86_64

GLOBAL_BUILD := $(LAUNCH_ROOT)build
GLOBAL_BIN   := $(LAUNCH_ROOT)bin

all: debug

# 4. DIRECT EXECUTION LOOP (Cascadeert strak omlaag naar de sub-orchestrators)
debug release clean test install: directories
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			echo "=============================================================================="; \
			echo "Entering Layer: $$dir -> Target: $@"; \
			echo "=============================================================================="; \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) $@ || exit 1; \
		fi \
	done

# 5. UTILITIES
directories:
	@mkdir -p $(GLOBAL_BUILD)
	@mkdir -p $(GLOBAL_BIN)

deep_clean:
	@echo "Removing centralized build and binary directories from $(LAUNCH_ROOT)..."
	rm -rf $(GLOBAL_BUILD) $(GLOBAL_BIN)

.PHONY: all debug release clean test install directories deep_clean

