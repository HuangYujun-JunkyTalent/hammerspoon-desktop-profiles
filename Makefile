LUA ?= lua
LUAC ?= luac
LUA_FILES := $(shell find . -name '*.lua' -not -path './.git/*')
HAMMERSPOON_LOADER := $(HOME)/.hammerspoon/init.lua

.PHONY: check syntax lint format format-check test launcher-scripts check-launcher-scripts install-loader
.PHONY: enable-desktop-shortcuts
.PHONY: asyar-extension-settings check-asyar-extension-settings check-asyar-extension link-asyar-extension
.PHONY: check-asyar-window-tiling link-asyar-window-tiling
.PHONY: check-asyar-trash link-asyar-trash

check: syntax lint format-check test check-launcher-scripts check-asyar-extension-settings

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
	bash -n tools/enable_desktop_shortcuts.sh
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

check-asyar-window-tiling:
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

enable-desktop-shortcuts:
	sh tools/enable_desktop_shortcuts.sh
