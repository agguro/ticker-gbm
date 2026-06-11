# ==============================================================================
# ASM-LINUX-FRAMEWORK: SUBROOT LAYER ORCHESTRATOR (Kernels Root)
# ==============================================================================

# 1. DYNAMIC DISCOVERY
# Zoekt naar alle submappen binnen kernels die een Makefile bevatten
SUBDIRS := $(patsubst %/,%,$(dir $(shell find . -mindepth 2 -maxdepth 2 -name Makefile)))

# Zorg dat de PARENTROOT bekend is mochten we hier direct 'make' aanroepen
ifndef PARENTROOT
    export PARENTROOT := $(CURDIR)/../
endif

all: debug

# 2. EXECUTION LOOP
debug release clean:
	@for dir in $(SUBDIRS); do \
		echo "=============================================================================="; \
		echo "Entering Subroot Layer: ./kernels/$$dir -> Target: $@"; \
		echo "=============================================================================="; \
		$(MAKE) -C $$dir $@ || exit 1; \
	done

.PHONY: all debug release clean

