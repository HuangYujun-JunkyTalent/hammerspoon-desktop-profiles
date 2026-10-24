import type { NotificationOptions, SpawnParams } from 'asyar-sdk/contracts';

// Asyar 4.14 drops the output and the end of a spawn of a worker, and delivers them to a view
// alone, so each command is one AppleScript that decides and reports inside `osascript`, and the
// worker learns only whether Asyar started the script.

export const OSASCRIPT_PATH = '/usr/bin/osascript';

const FINDER_BUNDLE_PATH = '/System/Library/CoreServices/Finder.app';
const FINDER_STRINGS_TABLE = 'LocalizableMerged';

/** AppleScript raises this error number when the user chooses the cancel button of an alert. */
const USER_CANCELLED_ERROR_NUMBER = -128;

/** A string of the Finder, by its key in `LocalizableMerged.strings`, with its English text. */
export interface FinderString {
  key: string;
  english: string;
}

/**
 * The words of the confirmation that Finder, Empty Trash shows, with the English text of
 * `en.lproj/LocalizableMerged.strings` in the Finder of macOS 27.0.1.
 * The script reads each string in the language of the user, and takes the English text when the
 * Finder no longer has the key.
 */
export const EMPTY_TRASH_CONFIRMATION = {
  message: {
    key: 'A15',
    english: 'Are you sure you want to permanently erase the items in the Trash?',
  },
  informativeText: { key: 'A16', english: 'You can’t undo this action.' },
  emptyButton: { key: 'AL10', english: 'Empty Trash' },
  cancelButton: { key: 'AL1', english: 'Cancel' },
} as const satisfies Record<string, FinderString>;

export const TRASH_IS_EMPTY_NOTICE = 'The Trash is empty.';

export function quoteAppleScriptString(text: string): string {
  return `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function readFinderStringLines(variable: string, finderString: FinderString): string[] {
  const key = quoteAppleScriptString(finderString.key);
  const table = quoteAppleScriptString(FINDER_STRINGS_TABLE);
  const english = quoteAppleScriptString(finderString.english);
  return [
    `set ${variable} to localized string ${key} from table ${table} in bundle finderBundle`,
    `if ${variable} is ${key} then set ${variable} to ${english}`,
  ];
}

function indent(lines: readonly string[]): string[] {
  return lines.map((line) => `\t${line}`);
}

/**
 * Wraps `bodyLines` so that an error shows as a notification titled `failureTitle`, and a
 * cancel of the user shows nothing.
 */
function reportErrorsAsNotification(
  failureTitle: string,
  bodyLines: readonly string[],
): string[] {
  return [
    'try',
    ...indent(bodyLines),
    'on error errorMessage number errorNumber',
    `\tif errorNumber is not ${USER_CANCELLED_ERROR_NUMBER} then ` +
      `display notification errorMessage with title ${quoteAppleScriptString(failureTitle)}`,
    'end try',
  ];
}

export const OPEN_TRASH_SCRIPT: readonly string[] = reportErrorsAsNotification('Trash failed', [
  'tell application "Finder"',
  '\tactivate',
  '\topen trash',
  'end tell',
]);

/**
 * Counts the items in the Trash, shows the confirmation of the Finder when there are any, and
 * empties the Trash only after the user chooses the button that empties.
 * The confirmation shows in the Finder, so that the alert carries the icon of the Finder, and its
 * timeout keeps the alert open as long as the user needs, where the default of AppleScript is two
 * minutes.
 * The erase turns the warning of the Finder off for the command alone, because the user has
 * confirmed already, and restores the setting of the user also when the erase fails.
 */
export const EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT: readonly string[] = [
  `set finderBundle to POSIX file ${quoteAppleScriptString(FINDER_BUNDLE_PATH)} as alias`,
  ...readFinderStringLines('messageText', EMPTY_TRASH_CONFIRMATION.message),
  ...readFinderStringLines('informativeText', EMPTY_TRASH_CONFIRMATION.informativeText),
  ...readFinderStringLines('emptyLabel', EMPTY_TRASH_CONFIRMATION.emptyButton),
  ...readFinderStringLines('cancelLabel', EMPTY_TRASH_CONFIRMATION.cancelButton),
  ...reportErrorsAsNotification('Empty Trash failed', [
    'tell application "Finder" to set itemCount to count of items of trash',
    'if itemCount is 0 then',
    `\tdisplay notification ${quoteAppleScriptString(TRASH_IS_EMPTY_NOTICE)} ` +
      `with title ${quoteAppleScriptString('Empty Trash')}`,
    '\treturn',
    'end if',
    'tell application "Finder"',
    '\tactivate',
    '\twith timeout of 86400 seconds',
    '\t\tset alertReply to display alert messageText message informativeText ' +
      'buttons {cancelLabel, emptyLabel} default button emptyLabel cancel button cancelLabel',
    '\tend timeout',
    'end tell',
    'if button returned of alertReply is emptyLabel then',
    '\ttell application "Finder"',
    '\t\tset warnsBeforeEmptying to warns before emptying of trash',
    '\t\tset warns before emptying of trash to false',
    '\t\ttry',
    '\t\t\twith timeout of 3600 seconds',
    '\t\t\t\tempty trash',
    '\t\t\tend timeout',
    '\t\ton error emptyErrorMessage number emptyErrorNumber',
    '\t\t\tset warns before emptying of trash to warnsBeforeEmptying',
    '\t\t\terror emptyErrorMessage number emptyErrorNumber',
    '\t\tend try',
    '\t\tset warns before emptying of trash to warnsBeforeEmptying',
    '\tend tell',
    'end if',
  ]),
];

export function buildOsascriptSpawn(scriptLines: readonly string[]): SpawnParams {
  return { program: OSASCRIPT_PATH, args: scriptLines.flatMap((line) => ['-e', line]) };
}

const TRASH_COMMAND_SCRIPTS: Readonly<Record<string, readonly string[]>> = {
  trash: OPEN_TRASH_SCRIPT,
  'empty-trash': EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT,
};

export function findTrashCommandScript(commandId: string): readonly string[] | null {
  return Object.hasOwn(TRASH_COMMAND_SCRIPTS, commandId) ? TRASH_COMMAND_SCRIPTS[commandId] : null;
}

/** The notification of a command whose script Asyar did not start or that failed in the worker. */
export function buildFailureNotification(
  commandName: string,
  failure: string,
): NotificationOptions {
  return { title: `${commandName} failed`, body: failure };
}
