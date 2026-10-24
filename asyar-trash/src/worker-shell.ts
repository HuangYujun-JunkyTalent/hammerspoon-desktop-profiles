// Asyar 4.14 runs the background bundle of an extension as a dedicated Web Worker, which has no
// `window`. `ShellServiceProxy.spawn` of the SDK listens for the output of the process with
// `window.addEventListener`, and throws a ReferenceError in the worker. Asyar also drops the
// output and the end of a spawn of a worker, and delivers them to a view alone. This module sends
// the same `shell:spawn` through the broker of the SDK, and reports whether Asyar started the
// program.

import type { SpawnParams } from 'asyar-sdk/contracts';

/** Whether Asyar started a script, and the reason when it did not. */
export interface ScriptStart {
  spawnError?: string;
}

export type AppleScriptStarter = (scriptLines: readonly string[]) => Promise<ScriptStart>;

/** Sends `shell:spawn` to Asyar, which answers once the program has started or failed to start. */
export type InvokeSpawn = (payload: SpawnParams & { spawnId: string }) => Promise<unknown>;

export async function startProgramInWorker(
  invokeSpawn: InvokeSpawn,
  spawnId: string,
  params: SpawnParams,
): Promise<ScriptStart> {
  try {
    await invokeSpawn({ ...params, spawnId });
    return {};
  } catch (error) {
    return { spawnError: `SPAWN_FAILED: ${error instanceof Error ? error.message : String(error)}` };
  }
}
