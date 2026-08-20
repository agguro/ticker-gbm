# ==============================================================================
# Root Multi-Architecture Makefile
# ==============================================================================

.PHONY: all debug release clean test

all: debug

debug:
	@$(MAKE) --no-print-directory -C cuda debug
	@$(MAKE) --no-print-directory -C x86_64 debug

release:
	@$(MAKE) --no-print-directory -C cuda release
	@$(MAKE) --no-print-directory -C x86_64 release

clean:
	@echo "Cleaning up entire build tree..."
	rm -rf build
	@$(MAKE) --no-print-directory -C cuda clean
	@$(MAKE) --no-print-directory -C x86_64 clean

test:
	@if [ -f test/run_tests.sh ]; then ./test/run_tests.sh; fi
