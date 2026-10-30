import { describe, expect, it } from 'vitest';
import manifest from '../manifest.json';
import { buildTrashUrl } from './trash-commands';

describe('buildTrashUrl', () => {
  it('gives the URL of every command of the manifest', () => {
    const urls = manifest.commands.map((command) => buildTrashUrl(command.id, 'trash'));
    expect(urls).toEqual([
      'hammerspoon://trash?command=trash',
      'hammerspoon://trash?command=empty-trash',
    ]);
  });

  it('opens the URLs of the setting url_event_name', () => {
    expect(buildTrashUrl('trash', 'bin')).toBe('hammerspoon://bin?command=trash');
  });
});
