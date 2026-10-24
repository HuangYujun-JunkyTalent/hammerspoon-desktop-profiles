import { describe, expect, it, vi } from 'vitest';
import type { Extension, ExtensionContext, IOpenerService } from 'asyar-sdk/contracts';

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

vi.mock('./settings.generated.json', () => ({ default: { urlEventName: 'tiles' } }));

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
    await registered.extension?.executeCommand('tile-fill');
    expect(opened).toEqual(['hammerspoon://tiles?position=fill']);
  });
});
