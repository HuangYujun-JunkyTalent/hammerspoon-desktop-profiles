// Prints the windows of the normal layer that the window server of macOS knows, on every desktop,
// as a JSON array of objects with the id, the process id of the owner, the title and the frame.
// `window_inventory.lua` runs it with `osascript -l JavaScript`, because Hammerspoon 1.1.1 reaches
// through accessibility only the windows of the desktops in view.
// The title is empty unless the process that starts the script has the permission for Screen
// Recording.

ObjC.import('CoreGraphics');

const NORMAL_LAYER = 0;

function run() {
  const windows = ObjC.deepUnwrap(
    ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)),
  );
  const rows = windows
    .filter((window) => window.kCGWindowLayer === NORMAL_LAYER)
    .map((window) => ({
      window_id: window.kCGWindowNumber,
      pid: window.kCGWindowOwnerPID,
      title: window.kCGWindowName || '',
      x: Math.round(window.kCGWindowBounds.X),
      y: Math.round(window.kCGWindowBounds.Y),
      w: Math.round(window.kCGWindowBounds.Width),
      h: Math.round(window.kCGWindowBounds.Height),
    }));
  return JSON.stringify(rows);
}
