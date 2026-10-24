// The worker of the extension: it starts the AppleScript of a command of the manifest through
// /usr/bin/osascript, and sends a notification when Asyar does not start it.

import {
  ExtensionContext as WorkerExtensionContext,
  extensionBridge,
  messageBroker,
} from 'asyar-sdk/worker';
import type {
  Extension,
  ExtensionContext,
  IFeedbackService,
  ILogService,
} from 'asyar-sdk/contracts';

import manifest from '../manifest.json';
import {
  buildFailureNotification,
  buildOsascriptSpawn,
  findTrashCommandScript,
} from './trash-commands';
import { type AppleScriptStarter, type ScriptStart, startProgramInWorker } from './worker-shell';

/** Asyar answers `shell:spawn` after the user has chosen whether to trust the program. */
const SPAWN_ANSWER_TIMEOUT_MS = 120_000;

const startAppleScriptInWorker: AppleScriptStarter = (scriptLines) =>
  startProgramInWorker(
    (payload) =>
      messageBroker.invoke('shell:spawn', { ...payload }, manifest.id, SPAWN_ANSWER_TIMEOUT_MS),
    crypto.randomUUID(),
    buildOsascriptSpawn(scriptLines),
  );

class TrashExtension implements Extension {
  private feedback?: IFeedbackService;
  private log?: ILogService;

  async initialize(context: ExtensionContext): Promise<void> {
    this.feedback = context.getService<IFeedbackService>('feedback');
    this.log = context.getService<ILogService>('log');
  }

  async activate(): Promise<void> {}

  async deactivate(): Promise<void> {}

  async executeCommand(commandId: string): Promise<unknown> {
    const scriptLines = findTrashCommandScript(commandId);
    const commandName = manifest.commands.find((declared) => declared.id === commandId)?.name;
    if (!scriptLines || !commandName) {
      this.log?.warn(`the command ${commandId} is unknown to Trash`);
      return undefined;
    }
    // An error that a command throws reaches only the console of the hidden worker, so the worker
    // turns it into a failure that the log of Asyar and a notification show.
    let start: ScriptStart;
    try {
      start = await startAppleScriptInWorker(scriptLines);
    } catch (error) {
      start = { spawnError: String(error) };
    }
    if (start.spawnError) {
      this.log?.error(`${commandName}: ${start.spawnError}`);
      await this.feedback?.sendBackground(buildFailureNotification(commandName, start.spawnError));
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
