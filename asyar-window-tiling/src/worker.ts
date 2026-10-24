// The worker of the extension: it opens the URL of the window tiling of Hammerspoon when one of the
// commands of the manifest runs.

import { ExtensionContext as WorkerExtensionContext, extensionBridge } from 'asyar-sdk/worker';
import type { Extension, ExtensionContext, ILogService, IOpenerService } from 'asyar-sdk/contracts';

import manifest from '../manifest.json';
import settings from './settings.generated.json';
import { findTilingUrl } from './tiling-commands';

class WindowTilingExtension implements Extension {
  private opener?: IOpenerService;
  private log?: ILogService;

  async initialize(context: ExtensionContext): Promise<void> {
    this.opener = context.getService<IOpenerService>('opener');
    this.log = context.getService<ILogService>('log');
  }

  async activate(): Promise<void> {}

  async deactivate(): Promise<void> {}

  async executeCommand(commandId: string): Promise<unknown> {
    const url = findTilingUrl(commandId, settings.urlEventName);
    if (!url) {
      this.log?.warn(`the command ${commandId} is unknown to Window Tiling`);
      return undefined;
    }
    await this.opener?.openUrl(url);
    return undefined;
  }

  onUnload = (): void => {};
}

const workerContext = new WorkerExtensionContext();
workerContext.setExtensionId(manifest.id);

extensionBridge.registerManifest(manifest as never);
extensionBridge.registerExtensionImplementation(manifest.id, new WindowTilingExtension());
// Asyar 4.14 loads the worker and calls neither initialize() nor activate(), so the worker calls
// both.
void extensionBridge.initializeExtensions().then(() => extensionBridge.activateExtensions());
