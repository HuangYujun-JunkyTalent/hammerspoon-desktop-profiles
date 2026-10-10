LUA ?= lua
LUAC ?= luac
LUA_FILES := $(shell find . -name '*.lua' -not -path './.git/*')
HAMMERSPOON_LOADER := $(HOME)/.hammerspoon/init.lua

.PHONY: check syntax lint format format-check test install-loader

check: syntax lint format-check test

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

install-loader:
	@if [ -e "$(HAMMERSPOON_LOADER)" ]; then \
		echo "$(HAMMERSPOON_LOADER) exists and was left unchanged"; \
	else \
		mkdir -p "$(dir $(HAMMERSPOON_LOADER))"; \
		printf 'dofile("%s/init.lua")\n' "$(CURDIR)" > "$(HAMMERSPOON_LOADER)"; \
		echo "wrote $(HAMMERSPOON_LOADER)"; \
	fi
