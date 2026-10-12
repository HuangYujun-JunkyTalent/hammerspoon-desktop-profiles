const URL_PREFIX = 'hammerspoon://window-tiling?position=';
const TILING_COMMAND_PATTERN = /^tile-([a-z-]+)$/;

/**
 * The URL of the window tiling of Hammerspoon that a command opens, or null for an unknown id.
 * The id of a command is `tile-` followed by the position, and Hammerspoon checks the position.
 */
export function findTilingUrl(commandId: string): string | null {
  const match = TILING_COMMAND_PATTERN.exec(commandId);
  return match ? `${URL_PREFIX}${match[1]}` : null;
}
