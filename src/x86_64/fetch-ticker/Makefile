# ==============================================================================
# UNIVERSAL STANDALONE CPU TOOL MAKEFILE (V4.3 - ABSOLUTELY DYNAMIC & FLATOUT)
# ==============================================================================

# 1. DYNAMIC POSITION & IDENTITY IDENTIFICATION
CURRENT_DIR  := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The program name is derived EXACTLY from the current directory name!
NAME         := $(notdir $(CURRENT_DIR))

ifndef PARENTROOT
    # Standalone fallback: Dynamically locate the repository root by searching upwards for the main Makefile
    ROOT         := $(dir $(abspath $(shell cv=$(CURRENT_DIR); while [ "$$cv" != "/" ] && [ ! -f "$$cv/Makefile" -o "$$cv" = "$(CURRENT_DIR)" ]; do cv=$$(dirname "$$cv"); done; echo "$$cv")))/
    PROJECT_BASE := tools
else
    ROOT         := $(PARENTROOT)
    # Extract everything between $(ROOT) and /src/ dynamically.
    # This captures 'projects/ticker-gbm', 'basics/gpu_clock', etc., flawlessly!
    PROJECT_BASE := $(shell echo "$(CURRENT_DIR)" | sed -E 's|.*$(ROOT)||; s|/src/.*||')
endif

# 2. GLOBAL PARAMETERS
MODE         ?= debug

# 3. SYSTEM PATHS (Dynamically flattened into the main project directory root)
BIN_DIR      := $(ROOT)bin/$(MODE)/$(PROJECT_BASE)
BUILD_DIR    := $(ROOT)build/$(MODE)/$(PROJECT_BASE)/$(NAME)

# 4. FILENAMES & TARGETS (Fully coupled dynamically to the directory identity)
SRC_HOST     := $(NAME).s
OBJ          := $(BUILD_DIR)/$(NAME).o
TARGET       := $(BIN_DIR)/$(NAME)

# --- DYNAMIC CONFIGURATION VIA MAKEFILELISTS.MK (For project-specific links) ---
-include MakefileLists.mk
# --------------------------------------------------------------------

# 5. TOOLCHAIN & FLAGS (Pure bare-metal assembler and linker)
AS           := as
LD           := ld

ASFLAGS      := --64

# Scan the source file dynamically to check if it uses SSL, if so, force OpenSSL flags
NEED_SSL     := $(shell grep -q "SSL\|BIO" $(SRC_HOST) 2>/dev/null && echo "yes" || echo "no")

ifeq ($(NEED_SSL),yes)
    LDFLAGS  := -m elf_x86_64 -L/usr/lib/x86_64-linux-gnu -lc -lssl -lcrypto $(EXTRA_LDFLAGS)
else
    LDFLAGS  := -m elf_x86_64 -L/usr/lib/x86_64-linux-gnu -lc $(EXTRA_LDFLAGS)
endif

# 6. MODE CONFIGURATION
ifeq ($(MODE),debug)
    ASFLAGS    += -g
    LDFLAGS    += -g
    MSG        := "Build Mode: DEBUG"
else
    LDFLAGS    += -s
    MSG        := "Build Mode: RELEASE"
endif

all: build_pipeline

debug:
	@$(MAKE) MODE=debug build_pipeline

release:
	@$(MAKE) MODE=release build_pipeline

build_pipeline: info directories $(TARGET)

# 7. COMPILATION RULES
info:
	@echo "=============================================================================="
	@echo $(MSG)
	@echo "Project Base: $(PROJECT_BASE)"
	@echo "Program Name: $(NAME)"
	@echo "Host Source:  $(SRC_HOST)"
	@echo "Target:       $(TARGET)"
	@echo "=============================================================================="

directories:
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(BUILD_DIR)

# Assemble host x86_64 assembly code
$(OBJ): $(SRC_HOST)
	@echo "[CPU] Assembling Tool Code..."
	$(AS) $(ASFLAGS) -c $< -o $@

# Link the final host executable file
$(TARGET): $(OBJ)
	@echo "[LINK] Tying object to dynamic libraries..."
	$(LD) $(OBJ) $(LDFLAGS) -o $(TARGET)
	@echo ">>> TOOL BUILD COMPLETE: $(TARGET)"

# 8. CLEANUP
.PHONY: all debug release build_pipeline info directories clean

clean:
	@echo "Cleaning up build modes for $(NAME)..."
	rm -rf $(BUILD_DIR)
	@# Only remove the specific binary to avoid clearing the whole flattened project directory
	rm -f $(TARGET)