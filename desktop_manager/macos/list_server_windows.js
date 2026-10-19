// Prints the windows of the normal layer that the window server of macOS knows, on every desktop,
// as a JSON array of objects with the id, the process id of the owner, the title, the frame and
// whether the window server shows the window.
// `window_inventory.lua` runs it with `osascript -l JavaScript`, because Hammerspoon reaches
// through accessibility only the windows of the desktops in view.
// The title is empty unless the process that starts the script has the permission for Screen
// Recording.
// An application may keep a window that it closed for later, such as a window of Tailscale or the
// "New Event" window of Calendar, and `hs.spaces.windowsForSpace` still lists such a window on its
// desktop while it shows nowhere.
// `is_shown` follows the rule by which yabai lists the windows of a space, from the tags and the
// attributes that the private functions of SkyLight give each window, and the field is missing
// when those functions cannot be called.
// The values arrive as decimal strings of 64 bits, so the rule reads them as BigInt.

ObjC.import('CoreGraphics');

const NORMAL_LAYER = 0;

// Whether yabai counts a window with these tags and attributes as a window of its space.
function isListedByYabai(tags, attributes) {
  const isDocument = (tags & 0x1n) !== 0n || ((tags & 0x2n) !== 0n && (tags & 0x80000000n) !== 0n);
  const isOrderedIn = (attributes & 0x2n) !== 0n || (tags & 0x400000000000000n) !== 0n;
  const isOnOtherSpace = attributes <= 0x1n && (tags & 0x1300000000000000n) !== 0n;
  return isDocument && (isOrderedIn || isOnOtherSpace);
}

// Returns the ids of the windows that yabai would list among `windowIds`, and the ids whose tags
// were read, or null when SkyLight cannot be called.
function readShownWindowIds(windowIds) {
  try {
    ObjC.bindFunction('SLSMainConnectionID', ['int', []]);
    ObjC.bindFunction('SLSWindowQueryWindows', ['void *', ['int', 'id', 'int']]);
    ObjC.bindFunction('SLSWindowQueryResultCopyWindows', ['void *', ['void *']]);
    ObjC.bindFunction('SLSWindowIteratorAdvance', ['bool', ['void *']]);
    ObjC.bindFunction('SLSWindowIteratorGetWindowID', ['unsigned int', ['void *']]);
    ObjC.bindFunction('SLSWindowIteratorGetTags', ['unsigned long long', ['void *']]);
    ObjC.bindFunction('SLSWindowIteratorGetAttributes', ['unsigned long long', ['void *']]);
    if (windowIds.length === 0) {
      return null;
    }
    const query = $.SLSWindowQueryWindows($.SLSMainConnectionID(), $(windowIds), windowIds.length);
    const iterator = query ? $.SLSWindowQueryResultCopyWindows(query) : null;
    if (!iterator) {
      return null;
    }
    const shown = new Set();
    const read = new Set();
    while ($.SLSWindowIteratorAdvance(iterator)) {
      const windowId = Number($.SLSWindowIteratorGetWindowID(iterator));
      read.add(windowId);
      const tags = BigInt($.SLSWindowIteratorGetTags(iterator));
      const attributes = BigInt($.SLSWindowIteratorGetAttributes(iterator));
      if (isListedByYabai(tags, attributes)) {
        shown.add(windowId);
      }
    }
    return { shown, read };
  } catch (error) {
    return null;
  }
}

function run() {
  const windows = ObjC.deepUnwrap(
    ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll, $.kCGNullWindowID)),
  ).filter((window) => window.kCGWindowLayer === NORMAL_LAYER);
  const shown = readShownWindowIds(windows.map((window) => window.kCGWindowNumber));
  const rows = windows.map((window) => {
    const row = {
      window_id: window.kCGWindowNumber,
      pid: window.kCGWindowOwnerPID,
      title: window.kCGWindowName || '',
      x: Math.round(window.kCGWindowBounds.X),
      y: Math.round(window.kCGWindowBounds.Y),
      w: Math.round(window.kCGWindowBounds.Width),
      h: Math.round(window.kCGWindowBounds.Height),
    };
    if (shown && shown.read.has(row.window_id)) {
      row.is_shown = shown.shown.has(row.window_id);
    }
    return row;
  });
  return JSON.stringify(rows);
}
