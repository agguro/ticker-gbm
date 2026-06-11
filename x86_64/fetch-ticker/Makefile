# ==============================================================================
# LOW-LEVEL FRAMEWORK: TEMPLATE_HOST (Pure x86_64 Linux Host Blueprint)
# ==============================================================================

# 1. VARIABLES: Gekoppeld aan de geëxporteerde PROJECT_ROOT
CURRENT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
NAME          := $(notdir $(CURRENT_DIR))

# Als PROJECT_ROOT niet is gezet (bij handmatige losse aanroep), vallen we veilig terug
PROJECT_ROOT  ?= $(patsubst %/x86_64/$(NAME)/,%/,$(CURRENT_DIR)/)
ROOT          := $(PROJECT_ROOT)

# Vlakke structuur detectie
clean_dir     := $(patsubst %/,%,$(dir $(CURRENT_DIR)))
PARENT_DIR    := $(notdir $(clean_dir))
ifeq ($(PARENT_DIR),x86_64)
    CATEGORY  := .
else
    CATEGORY  := $(PARENT_DIR)
endif

MODE          ?= debug

# 2. SYSTEM PATHS: Gecentraliseerd in de echte project root!
ifeq ($(CATEGORY),.)
    BIN_DIR      := $(ROOT)bin/$(MODE)/x86_64/$(NAME)
    BUILD_DIR    := $(ROOT)build/$(MODE)/x86_64/$(NAME)
    KERNEL_DIR   := $(ROOT)kernels/$(NAME)
    KERNEL_BUILD := $(ROOT)build/$(MODE)/kernels/$(NAME)
    INSTALL_DIR  := $(HOME)/asm-multiarch/bin/cuda/$(NAME)
else
    BIN_DIR      := $(ROOT)bin/$(MODE)/x86_64/$(CATEGORY)/$(NAME)
    BUILD_DIR    := $(ROOT)build/$(MODE)/x86_64/$(CATEGORY)/$(NAME)
    KERNEL_DIR   := $(ROOT)kernels/$(CATEGORY)/$(NAME)
    KERNEL_BUILD := $(ROOT)build/$(MODE)/kernels/$(CATEGORY)/$(NAME)
    INSTALL_DIR  := $(HOME)/asm-multiarch/bin/cuda/$(CATEGORY)/$(NAME)
endif

INC_DIR      := $(ROOT)x86_64/include
LIB_DIR      ?= $(ROOT)x86_64/lib

# 3. FILENAMES & TARGETS
SRC_HOST     := $(NAME).s
OBJ          := $(BUILD_DIR)/$(NAME).o
LST          := $(BUILD_DIR)/$(NAME).lst
TARGET       := $(BIN_DIR)/$(NAME)

# --- DYNAMISCHE CONFIGURATIE VIA MAKEFILELISTS.MK ---
-include MakefileLists.mk

# Strip eventuele handmatige paden van de input en dwing de geresolveerde LIB_DIR af
LIB_SOURCES_BARE := $(notdir $(LIB_SOURCES))
LIB_SOURCES_FULL := $(addprefix $(LIB_DIR)/,$(LIB_SOURCES_BARE))

# Vertaal de library snippets naar unieke objectbestanden met OBJ_ prefix in de BUILD_DIR
EXTRA_OBJS   := $(patsubst $(LIB_DIR)/%.s,$(BUILD_DIR)/obj_%.o,$(LIB_SOURCES_FULL))
ALL_OBJS     := $(OBJ) $(EXTRA_OBJS)
# --------------------------------------------------------------------

# 4. TOOLCHAIN & FLAGS
AS           := as
LD           := ld

# Schakel alle ingebouwde implicit rules van GNU Make keihard uit!
.SUFFIXES:
%: %.c

# ASFLAGS gebruikt nu gegarandeerd de geresolveerde LIB_DIR uit MakefileLists.mk
ASFLAGS      := --64 -msyntax=att -mmnemonic=att -I$(BUILD_DIR) -I$(INC_DIR) -I$(LIB_DIR) -I$(KERNEL_DIR) -I$(KERNEL_BUILD)
LDFLAGS      := -m elf_x86_64 -dynamic-linker /lib64/ld-linux-x86-64.so.2 -L/usr/local/cuda/lib64 -L/usr/lib/x86_64-linux-gnu -lcuda -lc -lcrypto -lssl

# 5. MODE CONFIGURATION
ifeq ($(MODE),debug)
        ASFLAGS    += -g
        LDFLAGS    += -g
        MSG        := "Host Build Mode: DEBUG"
else
        LDFLAGS    += -s
        MSG        := "Host Build Mode: RELEASE"
endif

all: build_pipeline

debug:
	@$(MAKE) MODE=debug build_pipeline

release:
	@$(MAKE) MODE=release build_pipeline

test: build_pipeline
	@echo "=============================================================================="
	@echo "Running $(MODE) host test for $(NAME)..."
	@echo "=============================================================================="
	@$(TARGET)

install:
	@$(MAKE) MODE=release build_pipeline
	@echo "=============================================================================="
	@echo " Installing $(NAME) (RELEASE) to system target..."
	@echo " Target: $(INSTALL_DIR)/$(NAME)"
	@echo "=============================================================================="
	@mkdir -p $(INSTALL_DIR)
	@cp $(TARGET) $(INSTALL_DIR)/$(NAME)
	@echo "--> Installation completed successfully!"

# 6. COMPILATION RULES: Kogelvrij voor parallelle builds (-j8)
build_pipeline: info check_kernel $(TARGET)

info:
	@echo "=============================================================================="
	@echo $(MSG)
	@echo "Category:     $(CATEGORY)"
	@echo "Host Source:  $(SRC_HOST)"
	@if [ -n "$(LIB_SOURCES_BARE)" ]; then echo "Lib Sources:  $(LIB_SOURCES_BARE) (resolved via $(LIB_DIR)/)"; fi
	@echo "Target:       $(TARGET)"
	@echo "=============================================================================="

directories:
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(BUILD_DIR)

# Controleer en bouw automatisch de GPU guest kernel
check_kernel:
	@if [ -f $(KERNEL_DIR)/Makefile ]; then \
		echo "--> Checking GPU Guest Kernel dependencies in $(KERNEL_DIR)..."; \
		$(MAKE) -C $(KERNEL_DIR) MODE=$(MODE) ROOT=$(ROOT) CATEGORY=$(CATEGORY) NAME=$(NAME); \
	fi

# Regel voor het hoofdprogramma van de host (Wacht op kernel én mappen via |)
$(OBJ): $(SRC_HOST) check_kernel | directories
	$(AS) $(ASFLAGS) -c $(SRC_HOST) -o $(OBJ) -a=$(LST)

# Dynamische regel om de snippets op te pikken (Wacht op mappen via |)
$(BUILD_DIR)/obj_%.o: $(LIB_DIR)/%.s | directories
	$(AS) $(ASFLAGS) -c $< -o $@

# De linker combineert de host en de benodigde snippets
$(TARGET): $(ALL_OBJS) | directories
	$(LD) $(LDFLAGS) $(ALL_OBJS) -o $(TARGET)
	@echo "--> Host Binary linked successfully!"
	@echo "--> Build completed successfully!"

# 7. CLEANUP
.PHONY: all debug release test build_pipeline info directories check_kernel clean install

clean:
	@echo "Cleaning up host build modes for $(NAME)..."
	@if [ "$(CATEGORY)" = "." ]; then \
		rm -rf $(ROOT)build/debug/x86_64/$(NAME); \
		rm -rf $(ROOT)build/release/x86_64/$(NAME); \
		rm -rf $(ROOT)bin/debug/x86_64/$(NAME); \
		rm -rf $(ROOT)bin/release/x86_64/$(NAME); \
	else \
		rm -rf $(ROOT)build/debug/x86_64/$(CATEGORY)/$(NAME); \
		rm -rf $(ROOT)build/release/x86_64/$(CATEGORY)/$(NAME); \
		rm -rf $(ROOT)bin/debug/x86_64/$(CATEGORY)/$(NAME); \
		rm -rf $(ROOT)bin/release/x86_64/$(CATEGORY)/$(NAME); \
	fi
