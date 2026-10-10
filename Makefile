LUA ?= lua
LUAC ?= luac
LUA_FILES := $(shell find . -name '*.lua' -not -path './.git/*')
HAMMERSPOON_LOADER := $(HOME)/.hammerspoon/init.lua

.PHONY: check syntax lint format format-check test launcher-scripts check-launcher-scripts install-loader

check: syntax lint format-check test check-launcher-scripts

syntax:
	@for file in $(LUA_FILES); do $(LUAC) -p "$$file" || exit 1; done

lint:
	luacheck --quiet --formatter plain .

format:
	stylua .

format-check:
	stylua --check .

test:
	$(LUA) tests/run_tests.lua

launcher-scripts:
	mkdir -p launcher-scripts
	rm -f launcher-scripts/*.sh
	$(LUA) tools/write_launcher_scripts.lua launcher-scripts

check-launcher-scripts:
	@scratch=$$(mktemp -d); \
	$(LUA) tools/write_launcher_scripts.lua "$$scratch" && diff -r launcher-scripts "$$scratch"; \
	status=$$?; rm -rf "$$scratch"; \
	if [ $$status -ne 0 ]; then echo "launcher-scripts differs from the generator: run make launcher-scripts"; exit 1; fi
	@for file in launcher-scripts/*.sh; do \
		[ -x "$$file" ] || { echo "$$file is not executable"; exit 1; }; \
		bash -n "$$file" || exit 1; \
	done

install-loader:
	@if [ -e "$(HAMMERSPOON_LOADER)" ]; then \
		echo "$(HAMMERSPOON_LOADER) exists and was left unchanged"; \
	else \
		mkdir -p "$(dir $(HAMMERSPOON_LOADER))"; \
		printf 'dofile("%s/init.lua")\n' "$(CURDIR)" > "$(HAMMERSPOON_LOADER)"; \
		echo "wrote $(HAMMERSPOON_LOADER)"; \
	fi
