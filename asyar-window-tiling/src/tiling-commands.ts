const TILING_COMMAND_PATTERN = /^tile-([a-z-]+)$/;

/**
 * The URL of the window tiling of Hammerspoon that a command opens, or null for an unknown id.
 * The id of a command is `tile-` followed by the position, and Hammerspoon checks the position.
 * The host of the URL is the setting `url_event_name` of the window tiling.
 */
export function findTilingUrl(commandId: string, urlEventName: string): string | null {
  const match = TILING_COMMAND_PATTERN.exec(commandId);
  return match ? `hammerspoon://${urlEventName}?position=${match[1]}` : null;
}
