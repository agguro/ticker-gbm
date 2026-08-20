# ==============================================================================
# CUDA Components Makefile
# ==============================================================================

CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_ROOT    := $(abspath $(CURRENT_DIR)/..)
MODE        ?= debug

BUILD_DIR   := $(SRC_ROOT)/build/$(MODE)/cuda
BIN_DIR     := $(SRC_ROOT)/build/$(MODE)/cuda

PTXAS       := ptxas
NVDISASM    := nvdisasm

PTXASFLAGS  := -v --gpu-name=sm_61
ifeq ($(MODE),debug)
    PTXASFLAGS += --generate-line-info
else
    PTXASFLAGS += -O3
endif

NAME        := gbm_monte_carlo
PTX_SRC     := $(NAME).ptx
CUBIN       := $(BUILD_DIR)/$(NAME).cubin
SASS        := $(BUILD_DIR)/$(NAME).sass

.PHONY: all debug release clean

all: debug

debug:
	@$(MAKE) --no-print-directory MODE=debug build_cuda

release:
	@$(MAKE) --no-print-directory MODE=release build_cuda

build_cuda: directories $(CUBIN)
ifneq ($(MODE),release)
	$(NVDISASM) -g $(CUBIN) > $(SASS)
else
	@rm -f $(SASS)
endif

directories:
	@mkdir -p $(BUILD_DIR)

$(CUBIN): $(PTX_SRC) | directories
	$(PTXAS) $(PTXASFLAGS) $(PTX_SRC) -o $(CUBIN)
	@echo "--> CUDA kernel compiled successfully to $(CUBIN)"

clean:
	@echo "Cleaning CUDA artifacts..."
	rm -rf $(BUILD_DIR)
