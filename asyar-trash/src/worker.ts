// The worker of the extension: it runs the AppleScript of a command of the manifest through
// /usr/bin/osascript, and sends a notification for a result that the Finder does not show.

import { ExtensionContext as WorkerExtensionContext, extensionBridge } from 'asyar-sdk/worker';
import type {
  Extension,
  ExtensionContext,
  IFeedbackService,
  ILogService,
  IShellService,
} from 'asyar-sdk/contracts';

import manifest from '../manifest.json';
import {
  type AppleScriptResult,
  type AppleScriptRunner,
  buildOsascriptSpawn,
  buildResultNotification,
  findTrashCommand,
} from './trash-commands';

function runAppleScriptThrough(shell: IShellService): AppleScriptRunner {
  return (scriptLines) =>
    new Promise<AppleScriptResult>((resolve) => {
      const stdout: string[] = [];
      const stderr: string[] = [];
      const handle = shell.spawn(buildOsascriptSpawn(scriptLines));
      handle.onChunk((chunk) => (chunk.stream === 'stdout' ? stdout : stderr).push(chunk.data));
      handle.onDone((exitCode) =>
        resolve({ exitCode, stdout: stdout.join('\n'), stderr: stderr.join('\n') }),
      );
      handle.onError((error) =>
        resolve({
          stdout: stdout.join('\n'),
          stderr: stderr.join('\n'),
          spawnError: `${error.code}: ${error.message}`,
        }),
      );
    });
}

class TrashExtension implements Extension {
  private shell?: IShellService;
  private feedback?: IFeedbackService;
  private log?: ILogService;

  async initialize(context: ExtensionContext): Promise<void> {
    this.shell = context.getService<IShellService>('shell');
    this.feedback = context.getService<IFeedbackService>('feedback');
    this.log = context.getService<ILogService>('log');
  }

  async activate(): Promise<void> {}

  async deactivate(): Promise<void> {}

  async executeCommand(commandId: string): Promise<unknown> {
    const command = findTrashCommand(commandId);
    const commandName = manifest.commands.find((declared) => declared.id === commandId)?.name;
    if (!command || !commandName || !this.shell) {
      this.log?.warn(`the command ${commandId} is unknown to Trash`);
      return undefined;
    }
    const result = await command(runAppleScriptThrough(this.shell));
    if (result.failure) {
      this.log?.error(`${commandName}: ${result.failure}`);
    }
    const notification = buildResultNotification(commandName, result);
    if (notification) {
      await this.feedback?.sendBackground(notification);
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
