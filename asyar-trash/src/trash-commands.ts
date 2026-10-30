/**
 * The URL of the trash tool of Hammerspoon that a command opens.
 * The host of the URL is the setting `url_event_name` of the trash tool, which runs the AppleScript
 * of the command, and which notifies an id that it does not know.
 */
export function buildTrashUrl(commandId: string, urlEventName: string): string {
  return `hammerspoon://${urlEventName}?command=${encodeURIComponent(commandId)}`;
}
