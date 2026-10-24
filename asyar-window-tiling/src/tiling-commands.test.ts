import { describe, expect, it } from 'vitest';
import manifest from '../manifest.json';
import { findTilingUrl } from './tiling-commands';

describe('findTilingUrl', () => {
  it('opens the position that the id names', () => {
    expect(findTilingUrl('tile-left-half', 'window-tiling')).toBe(
      'hammerspoon://window-tiling?position=left-half',
    );
    expect(findTilingUrl('tile-fill', 'window-tiling')).toBe(
      'hammerspoon://window-tiling?position=fill',
    );
  });

  it('opens the URLs of the setting url_event_name', () => {
    expect(findTilingUrl('tile-left-half', 'tiles')).toBe(
      'hammerspoon://tiles?position=left-half',
    );
  });

  it('gives a URL for every command of the manifest', () => {
    const urls = manifest.commands.map((command) => findTilingUrl(command.id, 'window-tiling'));
    expect(urls).toEqual(['hammerspoon://window-tiling?position=fill']);
  });

  it('gives null for an id of another form', () => {
    expect(findTilingUrl('profile-2', 'window-tiling')).toBeNull();
  });
});
