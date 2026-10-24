LUA ?= lua
LUAC ?= luac
LUA_FILES := $(shell find . -name '*.lua' -not -path './.git/*')
JAVASCRIPT_FOR_AUTOMATION_FILES := $(wildcard desktop_manager/macos/*.js)
HAMMERSPOON_LOADER := $(HOME)/.hammerspoon/init.lua

.PHONY: check syntax lint type-check format format-check test launcher-scripts check-launcher-scripts install-loader
.PHONY: asyar-extension-settings check-asyar-extension-settings check-asyar-extension link-asyar-extension
.PHONY: asyar-window-tiling-settings check-asyar-window-tiling-settings
.PHONY: check-asyar-window-tiling link-asyar-window-tiling
.PHONY: check-asyar-trash link-asyar-trash

check: syntax lint type-check format-check test check-launcher-scripts check-asyar-extension-settings \
	check-asyar-window-tiling-settings

syntax:
	@for file in $(LUA_FILES); do $(LUAC) -p "$$file" || exit 1; done
	@for file in $(JAVASCRIPT_FOR_AUTOMATION_FILES); do node --check "$$file" || exit 1; done

lint:
	luacheck --quiet --formatter plain .

type-check:
	lua-language-server --check . --checklevel=Warning --check_format=pretty

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
	bash -n tools/disable_macos_shortcut.sh
	@for file in launcher-scripts/*.sh; do \
		[ -x "$$file" ] || { echo "$$file is not executable"; exit 1; }; \
		bash -n "$$file" || exit 1; \
	done

asyar-extension-settings:
	$(LUA) tools/write_asyar_extension_settings.lua asyar-extension/src/settings.generated.json

check-asyar-extension-settings:
	@scratch=$$(mktemp); \
	$(LUA) tools/write_asyar_extension_settings.lua "$$scratch" && \
		diff asyar-extension/src/settings.generated.json "$$scratch"; \
	status=$$?; rm -f "$$scratch"; \
	if [ $$status -ne 0 ]; then \
		echo "asyar-extension/src/settings.generated.json differs from the generator:" \
			"run make asyar-extension-settings"; \
		exit 1; \
	fi

check-asyar-extension: check-asyar-extension-settings
	cd asyar-extension && npm run typecheck && npm test && npx asyar validate && npm run build

link-asyar-extension:
	cd asyar-extension && npx asyar link

asyar-window-tiling-settings:
	$(LUA) tools/write_asyar_window_tiling_settings.lua asyar-window-tiling/src/settings.generated.json

check-asyar-window-tiling-settings:
	@scratch=$$(mktemp); \
	$(LUA) tools/write_asyar_window_tiling_settings.lua "$$scratch" && \
		diff asyar-window-tiling/src/settings.generated.json "$$scratch"; \
	status=$$?; rm -f "$$scratch"; \
	if [ $$status -ne 0 ]; then \
		echo "asyar-window-tiling/src/settings.generated.json differs from the generator:" \
			"run make asyar-window-tiling-settings"; \
		exit 1; \
	fi

check-asyar-window-tiling: check-asyar-window-tiling-settings
	cd asyar-window-tiling && npm run typecheck && npm test && npx asyar validate && npm run build

link-asyar-window-tiling:
	cd asyar-window-tiling && npx asyar link

check-asyar-trash:
	cd asyar-trash && npm run typecheck && npm test && npx asyar validate && npm run build

link-asyar-trash:
	cd asyar-trash && npx asyar link

install-loader:
	@if [ -e "$(HAMMERSPOON_LOADER)" ]; then \
		echo "$(HAMMERSPOON_LOADER) exists and was left unchanged"; \
	else \
		mkdir -p "$(dir $(HAMMERSPOON_LOADER))"; \
		printf 'dofile("%s/init.lua")\n' "$(CURDIR)" > "$(HAMMERSPOON_LOADER)"; \
		echo "wrote $(HAMMERSPOON_LOADER)"; \
	fi
