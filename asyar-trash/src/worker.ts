// The worker of the extension: it opens the URL of the trash tool of Hammerspoon when one of the
// commands of the manifest runs, and Hammerspoon runs the AppleScript of the command.
// Asyar lists in its window every program that an extension starts, and leaves out the URLs that
// an extension opens, so the worker opens a URL.

import { ExtensionContext as WorkerExtensionContext, extensionBridge } from 'asyar-sdk/worker';
import type { Extension, ExtensionContext, ILogService, IOpenerService } from 'asyar-sdk/contracts';

import manifest from '../manifest.json';
import settings from './settings.generated.json';
import { buildTrashUrl } from './trash-commands';

class TrashExtension implements Extension {
  private opener?: IOpenerService;
  private log?: ILogService;

  async initialize(context: ExtensionContext): Promise<void> {
    this.opener = context.getService<IOpenerService>('opener');
    this.log = context.getService<ILogService>('log');
  }

  async activate(): Promise<void> {}

  async deactivate(): Promise<void> {}

  async executeCommand(commandId: string): Promise<unknown> {
    // An error that a command throws reaches only the console of the hidden worker, so the worker
    // sends it to the log of Asyar.
    try {
      await this.opener?.openUrl(buildTrashUrl(commandId, settings.urlEventName));
    } catch (error) {
      this.log?.error(`${commandId}: ${String(error)}`);
    }
    return undefined;
  }

  onUnload = (): void => {};
}

const workerContext = new WorkerExtensionContext();
workerContext.setExtensionId(manifest.id);

extensionBridge.registerManifest(manifest as never);
extensionBridge.registerExtensionImplementation(manifest.id, new TrashExtension());
// Asyar 4.14 loads the worker and calls neither initialize() nor activate(), so the worker calls
// both.
void extensionBridge.initializeExtensions().then(() => extensionBridge.activateExtensions());
