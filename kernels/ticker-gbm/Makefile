# ==============================================================================
# LOW-LEVEL FRAMEWORK: GPU KERNEL LEAF (ptxas blueprint)
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

PTXAS       := ptxas
PTXASFLAGS  := -v --gpu-name=sm_80 # Pas aan naar jouw GPU architectuur

ifeq ($(MODE),debug)
    PTXASFLAGS += -g -lineinfo
endif

# Default targets voor directe aanroep vanuit de kernels root
all: debug
debug release: build_kernel

# SPECIFIEK TARGET: Wordt aangeroepen door de host leaf om lussen te breken!
build_kernel: directories $(PTX_OBJ)

$(PTX_OBJ): $(PTX_SRC)
	$(PTXAS) $(PTXASFLAGS) $(PTX_SRC) -o $(PTX_OBJ)
	@echo "--> GPU Kernel $(NAME).ptx compiled successfully into $(PTX_OBJ)!"

directories:
	@mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all debug release clean build_kernel directories

