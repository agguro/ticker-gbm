# ==============================================================================
# x86_64 Components Makefile
# ==============================================================================

CURRENT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SRC_ROOT    := $(abspath $(CURRENT_DIR)/..)
MODE        ?= debug

BUILD_DIR   := $(SRC_ROOT)/build/$(MODE)/x86_64
BIN_DIR     := $(SRC_ROOT)/build/$(MODE)/x86_64
CUDA_BUILD  := $(SRC_ROOT)/build/$(MODE)/cuda

AS          := as
LD          := ld

# Voeg -I$(CUDA_BUILD) toe zodat .incbin de gbm_monte_carlo.cubin kan vinden
ASFLAGS     := --64 -msyntax=att -mmnemonic=att -I$(CUDA_BUILD)
LDFLAGS     := -m elf_x86_64 -dynamic-linker /lib64/ld-linux-x86-64.so.2 -lc -lcrypto -lssl -lcuda

ifeq ($(MODE),debug)
    ASFLAGS += -g
    LDFLAGS += -g
else
    LDFLAGS += -s
endif

TARGETS = fetch-ticker ticker-gbm

.PHONY: all debug release clean $(TARGETS)

all: debug

debug:
	@$(MAKE) --no-print-directory MODE=debug build_all

release:
	@$(MAKE) --no-print-directory MODE=release build_all

build_all: directories $(TARGETS)
ifeq ($(MODE),release)
	@rm -rf $(BUILD_DIR)/*.o $(BUILD_DIR)/*.lst 2>/dev/null || true
endif

directories:
	@mkdir -p $(BUILD_DIR)

fetch-ticker: directories
	@echo "Building x86_64 fetch-ticker [$(MODE)]..."
	$(AS) $(ASFLAGS) -c fetch-ticker.s -o $(BUILD_DIR)/fetch-ticker.o -a=$(BUILD_DIR)/fetch-ticker.lst
	$(LD) $(LDFLAGS) $(BUILD_DIR)/fetch-ticker.o -o $(BIN_DIR)/fetch-ticker

ticker-gbm: directories
	@echo "Building x86_64 ticker-gbm [$(MODE)]..."
	$(AS) $(ASFLAGS) -c ticker-gbm.s -o $(BUILD_DIR)/ticker-gbm.o -a=$(BUILD_DIR)/ticker-gbm.lst
	$(LD) $(LDFLAGS) $(BUILD_DIR)/ticker-gbm.o -o $(BIN_DIR)/ticker-gbm

clean:
	@echo "Cleaning x86_64 artifacts..."
	rm -f $(BUILD_DIR)/fetch-ticker* $(BUILD_DIR)/ticker-gbm*
