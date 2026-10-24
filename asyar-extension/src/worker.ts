// The worker of the extension: it keeps one item per profile in the search of Asyar, redraws the
// items when the state file of the Hammerspoon desktop manager changes, and opens the URL of the
// desktop manager when an item runs.

import { ExtensionContext as WorkerExtensionContext, extensionBridge } from 'asyar-sdk/worker';
import type {
  DynamicCommandRegistration,
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
  private refreshes: Promise<void> = Promise.resolve();

  async initialize(context: ExtensionContext): Promise<void> {
    this.commands = context.getService<ICommandService>('commands');
    this.files = context.getService<IFilesService>('files');
    this.fileWatcher = context.getService<IFileSystemWatcherService>('fsWatcher');
    this.opener = context.getService<IOpenerService>('opener');
    this.log = context.getService<ILogService>('log');
  }

  /**
   * Shows the items at once without the state, because the reads wait for the consent of the user
   * to the permissions, and a read without consent rejects only after ten seconds.
   */
  async activate(): Promise<void> {
    await this.registerItems(
      describeProfileCommands(readProfileSummary(null), settings.profileCount),
    );
    void this.refreshProfileItems();
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

  /** Starts the watch of the state file, unless it runs, and tries again at the next refresh. */
  private async watchStateFile(): Promise<void> {
    if (this.stateWatch) {
      return;
    }
    try {
      this.stateWatch = await this.fileWatcher?.watch([STATE_FILE_PATTERN]);
      this.stateWatch?.onChange(() => {
        void this.refreshProfileItems();
      });
    } catch (error) {
      this.log?.warn(`the state file of the desktop manager cannot be watched: ${String(error)}`);
    }
  }

  /** Reads the state and redraws the items, one refresh after the other. */
  private refreshProfileItems(): Promise<void> {
    this.refreshes = this.refreshes.then(async () => {
      await this.watchStateFile();
      let stateText: string | null = null;
      try {
        stateText = await this.readStateText();
      } catch (error) {
        this.log?.warn(`the state file of the desktop manager cannot be read: ${String(error)}`);
      }
      const summary = readProfileSummary(stateText);
      await this.registerItems(describeProfileCommands(summary, settings.profileCount));
    });
    return this.refreshes;
  }

  /**
   * Registers the items again when the active profile or a name changed.
   * Hammerspoon writes the state file after every change of a window, and most writes change
   * neither.
   */
  private async registerItems(items: DynamicCommandRegistration[]): Promise<void> {
    const itemsText = JSON.stringify(items);
    if (itemsText === this.registeredItems) {
      return;
    }
    try {
      await this.commands?.replaceDynamicCommands(items);
      this.registeredItems = itemsText;
    } catch (error) {
      this.log?.error(`the profiles could not be registered: ${String(error)}`);
    }
  }

  async executeCommand(commandId: string): Promise<unknown> {
    const url = findCommandUrl(commandId);
    if (!url) {
      this.log?.warn(`the command ${commandId} is unknown to Desktop Profiles`);
      return undefined;
    }
    await this.opener?.openUrl(url);
    // Running a command is where Asyar asks for the consent that the watch and the reads need.
    void this.refreshProfileItems();
    return undefined;
  }

  onUnload = (): void => {};
}

const workerContext = new WorkerExtensionContext();
workerContext.setExtensionId(manifest.id);

extensionBridge.registerManifest(manifest as never);
extensionBridge.registerExtensionImplementation(manifest.id, new DesktopProfilesExtension());
// Asyar 4.14 loads the worker and calls neither initialize() nor activate(), so the worker calls
// both, and the items show as soon as Asyar starts the worker.
void extensionBridge.initializeExtensions().then(() => extensionBridge.activateExtensions());
