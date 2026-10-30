import { describe, expect, it, vi } from 'vitest';
import type { Extension, ExtensionContext, ILogService, IOpenerService } from 'asyar-sdk/contracts';

const registered = vi.hoisted(() => ({ extension: undefined as Extension | undefined }));

vi.mock('asyar-sdk/worker', () => ({
  ExtensionContext: class {
    setExtensionId(): void {}
  },
  extensionBridge: {
    registerManifest: (): void => {},
    registerExtensionImplementation: (_id: string, extension: Extension): void => {
      registered.extension = extension;
    },
    initializeExtensions: async (): Promise<void> => {},
    activateExtensions: async (): Promise<void> => {},
  },
}));

vi.mock('./settings.generated.json', () => ({ default: { urlEventName: 'bin' } }));

describe('the worker', () => {
  it('opens the URL under the host of settings.generated.json', async () => {
    await import('./worker');
    const opened: string[] = [];
    const opener: Pick<IOpenerService, 'openUrl'> = {
      openUrl: async (url: string): Promise<void> => {
        opened.push(url);
      },
    };
    const context = {
      getService: (name: string) => (name === 'opener' ? opener : undefined),
    } as unknown as ExtensionContext;
    await registered.extension?.initialize(context);
    await registered.extension?.executeCommand('empty-trash');
    expect(opened).toEqual(['hammerspoon://bin?command=empty-trash']);
  });

  it('sends an error of the opening to the log of Asyar', async () => {
    await import('./worker');
    const errors: string[] = [];
    const opener: Pick<IOpenerService, 'openUrl'> = {
      openUrl: async (): Promise<void> => {
        throw new Error('refused');
      },
    };
    const log: Pick<ILogService, 'error'> = {
      error: (message: string): void => {
        errors.push(message);
      },
    };
    const context = {
      getService: (name: string) => ({ opener, log })[name],
    } as unknown as ExtensionContext;
    await registered.extension?.initialize(context);
    await registered.extension?.executeCommand('trash');
    expect(errors).toEqual(['trash: Error: refused']);
  });
});
