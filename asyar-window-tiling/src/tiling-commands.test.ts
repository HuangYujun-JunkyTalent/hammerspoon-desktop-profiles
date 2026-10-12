import { describe, expect, it } from 'vitest';
import manifest from '../manifest.json';
import { findTilingUrl } from './tiling-commands';

describe('findTilingUrl', () => {
  it('opens the position that the id names', () => {
    expect(findTilingUrl('tile-left-half')).toBe(
      'hammerspoon://window-tiling?position=left-half',
    );
    expect(findTilingUrl('tile-fill')).toBe('hammerspoon://window-tiling?position=fill');
  });

  it('gives a URL for every command of the manifest', () => {
    const positions = manifest.commands.map((command) => findTilingUrl(command.id));
    expect(positions).toEqual([
      'hammerspoon://window-tiling?position=fill',
      'hammerspoon://window-tiling?position=left-half',
      'hammerspoon://window-tiling?position=right-half',
      'hammerspoon://window-tiling?position=top-half',
      'hammerspoon://window-tiling?position=bottom-half',
    ]);
  });

  it('gives null for an id of another form', () => {
    expect(findTilingUrl('profile-2')).toBeNull();
  });
});
