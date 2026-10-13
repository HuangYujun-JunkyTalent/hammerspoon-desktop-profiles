import { describe, expect, it } from 'vitest';
import { type InvokeSpawn, startProgramInWorker } from './worker-shell';

const SPAWN_ID = 'spawn-1';
const PARAMS = { program: '/usr/bin/osascript', args: ['-e', 'return 1'] };

describe('startProgramInWorker', () => {
  it('sends shell:spawn with the program, the arguments and the spawn id', async () => {
    const payloads: unknown[] = [];
    const invokeSpawn: InvokeSpawn = async (payload) => {
      payloads.push(payload);
      return { streaming: true };
    };
    expect(await startProgramInWorker(invokeSpawn, SPAWN_ID, PARAMS)).toEqual({});
    expect(payloads).toEqual([{ ...PARAMS, spawnId: SPAWN_ID }]);
  });

  it('reports the error of shell:spawn when Asyar does not start the program', async () => {
    const refuse: InvokeSpawn = async () => {
      throw new Error('Binary "/usr/bin/osascript" is not trusted');
    };
    expect(await startProgramInWorker(refuse, SPAWN_ID, PARAMS)).toEqual({
      spawnError: 'SPAWN_FAILED: Binary "/usr/bin/osascript" is not trusted',
    });
  });
});
