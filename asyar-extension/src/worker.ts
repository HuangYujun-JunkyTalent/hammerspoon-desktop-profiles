// The worker of the extension: it keeps one item per profile in the search of Asyar, redraws the
// items when the state file of the Hammerspoon desktop manager changes, and opens the URL of the
// desktop manager when an item runs.

import { ExtensionContext as WorkerExtensionContext, extensionBridge } from 'asyar-sdk/worker';
import type {
  Extension,
  ExtensionContext,
  ICommandService,
  IFilesService,
  IFileSystemWatcherService,
  ILogService,
  IOpenerService,
  WatcherHandle,
} from 'asyar-sdk/contracts';

import manifest from '../manifest.json';
import settings from './settings.generated.json';
import { describeProfileCommands, findCommandUrl, readProfileSummary } from './profile-items';

// The manifest names the state file once, as the scope of the permission to read it.
const STATE_FILE_PATTERN = manifest.permissionArgs['files:read'][0];
const STATE_FILE_MAX_BYTES = 1024 * 1024;

class DesktopProfilesExtension implements Extension {
  private commands?: ICommandService;
  private files?: IFilesService;
  private fileWatcher?: IFileSystemWatcherService;
  private opener?: IOpenerService;
  private log?: ILogService;
  private stateWatch?: WatcherHandle;
  private registeredItems = '';

  async initialize(context: ExtensionContext): Promise<void> {
    this.commands = context.getService<ICommandService>('commands');
    this.files = context.getService<IFilesService>('files');
    this.fileWatcher = context.getService<IFileSystemWatcherService>('fsWatcher');
    this.opener = context.getService<IOpenerService>('opener');
    this.log = context.getService<ILogService>('log');
  }

  async activate(): Promise<void> {
    await this.registerProfileItems();
    this.stateWatch = await this.fileWatcher?.watch([STATE_FILE_PATTERN]);
    this.stateWatch?.onChange(() => {
      void this.registerProfileItems();
    });
  }

  async deactivate(): Promise<void> {
    await this.stateWatch?.dispose();
  }

  /** The text of the state file, or null before Hammerspoon has written one. */
  private async readStateText(): Promise<string | null> {
    // A read needs an absolute path, and a glob of the exact pattern resolves the home folder.
    const [statePath] = (await this.files?.glob(STATE_FILE_PATTERN)) ?? [];
    if (!statePath) {
      return null;
    }
    return (await this.files?.read(statePath, { maxBytes: STATE_FILE_MAX_BYTES })) ?? null;
  }

  /**
   * Registers the items again when the active profile or a name changed.
   * Hammerspoon writes the state file after every change of a window, and most writes change
   * neither.
   */
  private async registerProfileItems(): Promise<void> {
    let stateText: string | null = null;
    try {
      stateText = await this.readStateText();
    } catch (error) {
      this.log?.warn(`the state file of the desktop manager could not be read: ${String(error)}`);
    }
    const items = describeProfileCommands(readProfileSummary(stateText), settings.profileCount);
    const itemsText = JSON.stringify(items);
    if (itemsText === this.registeredItems) {
      return;
    }
    await this.commands?.replaceDynamicCommands(items);
    this.registeredItems = itemsText;
  }

  async executeCommand(commandId: string): Promise<unknown> {
    const url = findCommandUrl(commandId);
    if (!url) {
      this.log?.warn(`the command ${commandId} is unknown to Desktop Profiles`);
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
extensionBridge.registerExtensionImplementation(manifest.id, new DesktopProfilesExtension());
extensionBridge.initializeExtensions();
