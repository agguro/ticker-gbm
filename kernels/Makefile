# ==============================================================================
# ASM-LINUX-FRAMEWORK: SUBROOT LAYER ORCHESTRATOR (Kernels Layer)
# ==============================================================================

ifndef LAUNCH_ROOT
    export LAUNCH_ROOT := $(abspath $(CURDIR)/../)/
endif

# Kogelvrije discovery: we pakken alle mappen, maar filteren '.' en '..' expliciet uit!
ALL_DIRS := $(patsubst %/,%,$(dir $(wildcard */Makefile)))
SUBDIRS  := $(filter-out . ..,$(ALL_DIRS))

all: debug

debug release clean:
	@for dir in $(SUBDIRS); do \
		if [ -d $$dir ] && [ -f $$dir/Makefile ]; then \
			echo "=============================================================================="; \
			echo "Entering Subroot Layer: ./kernels/$$dir -> Target: $@"; \
			echo "=============================================================================="; \
			$(MAKE) -C $$dir LAUNCH_ROOT=$(LAUNCH_ROOT) $@ || exit 1; \
		fi \
	done

.PHONY: all debug release clean
