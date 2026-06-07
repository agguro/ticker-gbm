# ==============================================================================
# BARE-METAL GPU TEMPLATE: UNIVERSAL CONSOLIDATED LEAF (WITH INTERNAL TOOL LOOP)
# ==============================================================================

CURRENT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME         := $(notdir $(CURRENT_DIR))

ifndef PARENTROOT
    ROOT     := $(CURRENT_DIR)/
    CATEGORY := $(notdir $(patsubst %/,%,$(dir $(CURRENT_DIR))))
else
    ROOT     := $(PARENTROOT)
    CATEGORY := $(shell echo "$(CURRENT_DIR)" | sed -E 's/.*\/src\/(source\/)?([^\/]+)\/.*/\2/; s/.*\/projects\/.*/projects/')
endif

ARCH         := sm_61
MODE         ?= debug

BIN_DIR      := $(ROOT)bin/$(MODE)/$(CATEGORY)/$(NAME)
BUILD_DIR    := $(ROOT)build/$(MODE)/$(CATEGORY)/$(NAME)

SRC_DIR      := src/x86_64
KERNEL_DIR   := kernels

SRC_HOST     := $(SRC_DIR)/$(NAME).s
SRC_PTX      := $(KERNEL_DIR)/$(NAME).ptx

CUBIN        := $(BUILD_DIR)/$(NAME).cubin
OBJ          := $(BUILD_DIR)/$(NAME).o
TARGET       := $(BIN_DIR)/$(NAME)

-include MakefileLists.mk
LIB_DIR          := $(ROOT)src/lib
LIB_SOURCES_BARE := $(notdir $(LIB_SOURCES))
LIB_SOURCES_FULL := $(addprefix $(LIB_DIR)/,$(LIB_SOURCES_BARE))
EXTRA_OBJS       := $(patsubst $(LIB_DIR)/%.s,$(BUILD_DIR)/lib_%.o,$(LIB_SOURCES_FULL))
ALL_OBJS         := $(OBJ) $(EXTRA_OBJS)

AS           := as
LD           := ld
PTXAS        := ptxas

ASFLAGS      := --64 -I$(BUILD_DIR)
PTXFLAGS     := -v -arch=$(ARCH)
LDFLAGS      := -m elf_x86_64 -L/usr/local/cuda/lib64 -L/usr/lib/x86_64-linux-gnu -lcuda -lc

ifeq ($(MODE),debug)
    ASFLAGS    += -g
    LDFLAGS    += -g
    PTXFLAGS   += -lineinfo
    MSG        := "Build Mode: DEBUG"
else
    LDFLAGS    += -s
    PTXFLAGS   += -O3
    MSG        := "Build Mode: RELEASE"
endif

# Find internal tools with their own Makefiles deep in the src tree
INTERNAL_TOOLS := $(patsubst %/,%,$(dir $(shell find src/ -name Makefile 2>/dev/null)))

all: build_pipeline

debug:
	@$(MAKE) MODE=debug build_pipeline

release:
	@$(MAKE) MODE=release build_pipeline

test: build_pipeline
	@$(TARGET)

build_pipeline: info directories $(CUBIN) $(TARGET)
	@for tool in $(INTERNAL_TOOLS); do \
		echo "=============================================================================="; \
		echo "Entering Internal Tool Directory: $$tool -> Target: $(MODE)"; \
		echo "=============================================================================="; \
		$(MAKE) -C $$tool $(MODE) PARENTROOT=$(ROOT) || exit 1; \
	done

info:
	@echo "=============================================================================="
	@echo $(MSG)
	@echo "Category:     $(CATEGORY)"
	@echo "Project:      $(NAME)"
	@echo "Host Source:  $(SRC_HOST)"
	@echo "GPU Source:   $(SRC_PTX) -> $(CUBIN)"
	@echo "Target:       $(TARGET)"
	@echo "=============================================================================="

directories:
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(BUILD_DIR)

$(CUBIN): $(SRC_PTX)
	@echo "[GPU] Assembling PTX Kernel..."
	$(PTXAS) $(PTXFLAGS) $(SRC_PTX) -o $(CUBIN)

$(OBJ): $(SRC_HOST) $(CUBIN)
	@echo "[CPU] Assembling Host Code..."
	$(AS) $(ASFLAGS) -c $(SRC_HOST) -o $(OBJ)

$(BUILD_DIR)/lib_%.o: $(LIB_DIR)/%.s
	@mkdir -p $(BUILD_DIR)
	$(AS) $(ASFLAGS) -c $< -o $@

$(TARGET): $(ALL_OBJS)
	@echo "[LINK] Tying objects to libcuda.so..."
	$(LD) $(ALL_OBJS) $(LDFLAGS) -o $(TARGET)
	@echo ">>> BUILD COMPLETE: $(TARGET)"

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
	@for tool in $(INTERNAL_TOOLS); do $(MAKE) -C $$tool clean; done

.PHONY: all debug release test build_pipeline info directories clean
