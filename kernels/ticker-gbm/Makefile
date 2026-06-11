# ==============================================================================
# LOW-LEVEL FRAMEWORK: TEMPLATE_KERNEL (Pure GPU Guest Kernel Blueprint)
# ==============================================================================

# ==============================================================================
# LOW-LEVEL FRAMEWORK: TEMPLATE_KERNEL (Pure GPU Guest Kernel Blueprint)
# ==============================================================================

# 1. TOOLCHAIN DEFINITION (Hardcoded paths to prevent environment bleeding in sub-shells)
PTXAS    := /usr/bin/ptxas
NVDISASM := /usr/bin/nvdisasm

# Controleer fysiek of de binaries er daadwerkelijk staan
ifeq ($(wildcard $(PTXAS)),)
    $(error CRITICAL: 'ptxas' not found at $(PTXAS). Please install nvidia-cuda-toolkit!)
endif

ifeq ($(wildcard $(NVDISASM)),)
    $(error CRITICAL: 'nvdisasm' not found at $(NVDISASM). Please install nvidia-cuda-toolkit!)
endif

# 2. VARIABLES: Gekoppeld aan de geëxporteerde PROJECT_ROOT
CURRENT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME          := $(notdir $(CURRENT_DIR))

# Terugvaloptie voor losse aanroepen
PROJECT_ROOT  ?= $(patsubst %/kernels/$(NAME)/,%/,$(CURRENT_DIR)/)
ROOT          := $(PROJECT_ROOT)

# Vlakke structuur detectie
clean_dir     := $(patsubst %/,%,$(dir $(CURRENT_DIR)))
PARENT_DIR    := $(notdir $(clean_dir))
ifeq ($(PARENT_DIR),kernels)
    CATEGORY := .
else
    CATEGORY := $(PARENT_DIR)
endif

ARCHITECTURE := sm_61
MODE         ?= debug

# 3. SYSTEM PATHS: Gecentraliseerd!
ifeq ($(CATEGORY),.)
    BUILD_DIR := $(ROOT)build/$(MODE)/kernels/$(NAME)
else
    BUILD_DIR := $(ROOT)build/$(MODE)/kernels/$(CATEGORY)/$(NAME)
endif

# 4. FILENAMES & TARGETS
SRC_PTX       := $(NAME).ptx
CUBIN         := $(BUILD_DIR)/$(NAME).cubin
SASS          := $(BUILD_DIR)/$(NAME).sass

# 5. TOOLCHAIN FLAGS
PTXASFLAGS    := -v -arch=$(ARCHITECTURE)
NVFLAGS       :=

# 6. MODE CONFIGURATION
ifeq ($(MODE),debug)
        PTXASFLAGS += -lineinfo
        NVFLAGS    += -g
        MSG        := "Kernel Build Mode: DEBUG"
        PIPELINE_SASS := $(SASS)
else
        PTXASFLAGS += -O3
        MSG        := "Kernel Build Mode: RELEASE"
        PIPELINE_SASS :=
endif

all: build_pipeline

debug:
	@$(MAKE) MODE=debug build_pipeline

release:
	@$(MAKE) MODE=release build_pipeline

build_pipeline: info directories $(CUBIN) $(PIPELINE_SASS)

# 7. COMPILATION RULES
info:
	@echo "=============================================================================="
	@echo $(MSG)
	@echo "Category:     $(CATEGORY)"
	@echo "Architecture: $(ARCHITECTURE)"
	@echo "GPU Source:   $(SRC_PTX) -> $(CUBIN)"
	@if [ "$(MODE)" = "debug" ]; then echo "SASS Dump:    $(SASS)"; fi
	@echo "=============================================================================="

directories:
	@mkdir -p $(BUILD_DIR)

$(CUBIN): $(SRC_PTX)
	$(PTXAS) $(PTXASFLAGS) $(SRC_PTX) -o $(CUBIN)
	@echo "--> GPU Kernel assembled successfully via ptxas to $(CUBIN)"

$(SASS): $(CUBIN)
	$(NVDISASM) $(NVFLAGS) $(CUBIN) > $(SASS)
	@echo "--> SASS source disassembled successfully to $(SASS)"
	@echo "--> Build completed successfully!"

# 8. CLEANUP
.PHONY: all debug release build_pipeline info directories clean

clean:
	@echo "Cleaning up kernel build modes for $(NAME)..."
	@if [ "$(CATEGORY)" = "." ]; then \
		rm -rf $(ROOT)build/debug/kernels/$(NAME); \
		rm -rf $(ROOT)build/release/kernels/$(NAME); \
	else \
		rm -rf $(ROOT)build/debug/kernels/$(CATEGORY)/$(NAME); \
		rm -rf $(ROOT)build/release/kernels/$(CATEGORY)/$(NAME); \
	fi

