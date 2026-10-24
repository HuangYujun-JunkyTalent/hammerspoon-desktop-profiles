// Captures the windows whose ids follow the box, scales each capture with its proportions into the
// box, and prints one line per window as soon as it has the image:
// `<window id> <seconds of the capture> <data URL of the PNG, or none>`.
// `window_previews.lua` starts it as
// `osascript -l JavaScript capture_window_previews.js <box width> <box height> <window id> ...`,
// with the box in pixels, so that the capture has the permission for Screen Recording of
// Hammerspoon.
// A window whose points reach the box in one direction is captured at the resolution of its points,
// which has a quarter of the pixels on a Retina display, and a smaller window at the full
// resolution of its display, so that its preview keeps its detail.
// The helper prints `none` for a window that no longer exists or that macOS gives no image of.

ObjC.import('AppKit');
ObjC.import('CoreGraphics');

const LIST_OPTION_INCLUDING_WINDOW = 8;
const IMAGE_BOUNDS_IGNORE_FRAMING = 1;
const IMAGE_SHOULD_BE_OPAQUE = 2;
const IMAGE_BEST_RESOLUTION = 8;
const IMAGE_NOMINAL_RESOLUTION = 16;
const BITS_PER_COMPONENT = 8;
const ALPHA_PREMULTIPLIED_LAST = 1;
const INTERPOLATION_HIGH = 3;
const PNG_FILE_TYPE = 4;
const DATA_URL_PREFIX = 'data:image/png;base64,';

function readSecondsSinceBoot() {
  return $.NSProcessInfo.processInfo.systemUptime;
}

function writeLine(text) {
  const data = $(text + '\n').dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

// Returns the bounds of the window in points, or null when the window server no longer lists it.
function readWindowBounds(windowId) {
  const listed = ObjC.deepUnwrap(
    ObjC.castRefToObject($.CGWindowListCopyWindowInfo(LIST_OPTION_INCLUDING_WINDOW, windowId)),
  );
  const info = (listed || []).find((entry) => entry.kCGWindowNumber === windowId);
  return info ? info.kCGWindowBounds : null;
}

// Returns the PNG of the capture, scaled into the box, as a data URL.
function encodeScaledCapture(capture, captureWidth, captureHeight, box) {
  const scale = Math.min(box.width / captureWidth, box.height / captureHeight);
  const width = Math.max(1, Math.round(captureWidth * scale));
  const height = Math.max(1, Math.round(captureHeight * scale));
  const context = $.CGBitmapContextCreate(
    null,
    width,
    height,
    BITS_PER_COMPONENT,
    0,
    $.CGColorSpaceCreateDeviceRGB(),
    ALPHA_PREMULTIPLIED_LAST,
  );
  $.CGContextSetInterpolationQuality(context, INTERPOLATION_HIGH);
  $.CGContextDrawImage(context, $.CGRectMake(0, 0, width, height), capture);
  const png = $.NSBitmapImageRep.alloc
    .initWithCGImage($.CGBitmapContextCreateImage(context))
    .representationUsingTypeProperties(PNG_FILE_TYPE, $());
  return DATA_URL_PREFIX + png.base64EncodedStringWithOptions(0).js;
}

// Returns the seconds of the capture of the window, and its preview as a data URL or null.
function captureWindow(windowId, box) {
  const bounds = readWindowBounds(windowId);
  if (!bounds) {
    return { seconds: 0, dataUrl: null };
  }
  const reachesBox = bounds.Width >= box.width || bounds.Height >= box.height;
  const resolution = reachesBox ? IMAGE_NOMINAL_RESOLUTION : IMAGE_BEST_RESOLUTION;
  const started = readSecondsSinceBoot();
  const capture = $.CGWindowListCreateImage(
    $.CGRectNull,
    LIST_OPTION_INCLUDING_WINDOW,
    windowId,
    IMAGE_BOUNDS_IGNORE_FRAMING | IMAGE_SHOULD_BE_OPAQUE | resolution,
  );
  const seconds = readSecondsSinceBoot() - started;
  // JavaScript for Automation gives the image as a reference of Core Graphics, which has no test
  // for null, so the width tells whether macOS gave an image.
  const captureWidth = capture ? $.CGImageGetWidth(capture) : 0;
  const captureHeight = capture ? $.CGImageGetHeight(capture) : 0;
  if (captureWidth === 0 || captureHeight === 0) {
    return { seconds, dataUrl: null };
  }
  return { seconds, dataUrl: encodeScaledCapture(capture, captureWidth, captureHeight, box) };
}

function run(argv) {
  const box = { width: parseFloat(argv[0]), height: parseFloat(argv[1]) };
  for (const argument of argv.slice(2)) {
    const windowId = parseInt(argument, 10);
    let preview;
    try {
      preview = captureWindow(windowId, box);
    } catch (error) {
      preview = { seconds: 0, dataUrl: null };
    }
    writeLine(`${windowId} ${preview.seconds.toFixed(3)} ${preview.dataUrl || 'none'}`);
  }
}
