# ==============================================================================
# LOW-LEVEL FRAMEWORK: GPU KERNEL LEAF (ptxas + nvdisasm blueprint)
# ==============================================================================

CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME        := $(notdir $(CURRENT_DIR))

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURRENT_DIR)/../../)/
endif

MODE        ?= debug
BUILD_DIR   := $(LAUNCH_ROOT)build/$(MODE)/kernels/$(NAME)

PTX_SRC     := $(CURRENT_DIR)/$(NAME).ptx
PTX_OBJ     := $(BUILD_DIR)/$(NAME).cubin

# FIX: Voeg het SASS-doelbestand toe in de build-tree
SASS_DUMP   := $(BUILD_DIR)/$(NAME).sass

PTXAS       := ptxas
NVDISASM    := nvdisasm
PTXASFLAGS  := -v --gpu-name=sm_80 

ifeq ($(MODE),debug)
    PTXASFLAGS += --generate-line-info
endif

all: debug
debug release: build_kernel

# FIX: Neem $(SASS_DUMP) mee in de build pipeline bij debug/release
build_kernel: directories $(PTX_OBJ) $(SASS_DUMP)

$(PTX_OBJ): $(PTX_SRC)
	$(PTXAS) $(PTXASFLAGS) $(PTX_SRC) -o $(PTX_OBJ)
	@echo "--> GPU Kernel $(NAME).ptx compiled successfully into $(PTX_OBJ)!"

# FIX: Nieuwe regel om de CUBIN te disassembleren naar pure SASS machinecode!
$(SASS_DUMP): $(PTX_OBJ)
	@echo "--> Disassembling $(PTX_OBJ) into native SASS architecture..."
	$(NVDISASM) -g $(PTX_OBJ) > $(SASS_DUMP)
	@echo "--> SASS file generated successfully: $(SASS_DUMP)"

directories:
	@mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all debug release clean build_kernel directories
