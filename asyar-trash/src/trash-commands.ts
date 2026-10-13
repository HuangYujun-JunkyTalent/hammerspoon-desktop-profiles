import type { NotificationOptions, SpawnParams } from 'asyar-sdk/contracts';

export const OSASCRIPT_PATH = '/usr/bin/osascript';

const FINDER_BUNDLE_PATH = '/System/Library/CoreServices/Finder.app';
const FINDER_STRINGS_TABLE = 'LocalizableMerged';

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

export const CONFIRMED_REPLY = 'empty-confirmed';
export const CANCELLED_REPLY = 'cancelled';

export enum TrashOutcome {
  Opened = 'opened',
  Emptied = 'emptied',
  Cancelled = 'cancelled',
  TrashWasEmpty = 'trash-was-empty',
  Failed = 'failed',
}

export interface TrashCommandResult {
  outcome: TrashOutcome;
  failure?: string;
}

/**
 * What one run of `osascript` gave: its exit code when Asyar reports one, its output, and the error
 * of a start that failed.
 */
export interface AppleScriptResult {
  exitCode?: number;
  stdout: string;
  stderr: string;
  spawnError?: string;
}

export type AppleScriptRunner = (scriptLines: readonly string[]) => Promise<AppleScriptResult>;

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

export const OPEN_TRASH_SCRIPT: readonly string[] = [
  'tell application "Finder"',
  '\tactivate',
  '\topen trash',
  'end tell',
];

export const COUNT_TRASH_ITEMS_SCRIPT: readonly string[] = [
  'tell application "Finder" to return (count of items of trash) as text',
];

/**
 * Shows the confirmation in the Finder, so that the alert carries the icon of the Finder, and
 * prints `CONFIRMED_REPLY` only when the user chooses the button that empties.
 * The timeout keeps the alert open as long as the user needs, where the default of AppleScript is
 * two minutes.
 */
export const CONFIRMATION_SCRIPT: readonly string[] = [
  `set finderBundle to POSIX file ${quoteAppleScriptString(FINDER_BUNDLE_PATH)} as alias`,
  ...readFinderStringLines('messageText', EMPTY_TRASH_CONFIRMATION.message),
  ...readFinderStringLines('informativeText', EMPTY_TRASH_CONFIRMATION.informativeText),
  ...readFinderStringLines('emptyLabel', EMPTY_TRASH_CONFIRMATION.emptyButton),
  ...readFinderStringLines('cancelLabel', EMPTY_TRASH_CONFIRMATION.cancelButton),
  'tell application "Finder"',
  '\tactivate',
  '\ttry',
  '\t\twith timeout of 86400 seconds',
  '\t\t\tset alertReply to display alert messageText message informativeText ' +
    'buttons {cancelLabel, emptyLabel} default button emptyLabel cancel button cancelLabel',
  '\t\tend timeout',
  '\ton error number -128',
  `\t\treturn ${quoteAppleScriptString(CANCELLED_REPLY)}`,
  '\tend try',
  'end tell',
  'if button returned of alertReply is emptyLabel then ' +
    `return ${quoteAppleScriptString(CONFIRMED_REPLY)}`,
  `return ${quoteAppleScriptString(CANCELLED_REPLY)}`,
];

/**
 * Empties the Trash with the warning of the Finder turned off for the command alone, because the
 * user has confirmed already, and restores the setting of the user also when the command fails.
 */
export const EMPTY_TRASH_SCRIPT: readonly string[] = [
  'tell application "Finder"',
  '\tset warnsBeforeEmptying to warns before emptying of trash',
  '\tset warns before emptying of trash to false',
  '\ttry',
  '\t\twith timeout of 3600 seconds',
  '\t\t\tempty trash',
  '\t\tend timeout',
  '\ton error errorMessage number errorNumber',
  '\t\tset warns before emptying of trash to warnsBeforeEmptying',
  '\t\terror errorMessage number errorNumber',
  '\tend try',
  '\tset warns before emptying of trash to warnsBeforeEmptying',
  'end tell',
];

export function buildOsascriptSpawn(scriptLines: readonly string[]): SpawnParams {
  return { program: OSASCRIPT_PATH, args: scriptLines.flatMap((line) => ['-e', line]) };
}

function hasSucceeded(result: AppleScriptResult): boolean {
  const isExitCodeZeroOrUnreported = result.exitCode === undefined || result.exitCode === 0;
  return result.spawnError === undefined && isExitCodeZeroOrUnreported;
}

function describeFailure(result: AppleScriptResult): TrashCommandResult {
  const reason =
    result.spawnError ??
    (result.stderr.trim() || `osascript exited with status ${result.exitCode}`);
  return { outcome: TrashOutcome.Failed, failure: reason };
}

export async function openTrash(runAppleScript: AppleScriptRunner): Promise<TrashCommandResult> {
  const result = await runAppleScript(OPEN_TRASH_SCRIPT);
  return hasSucceeded(result) ? { outcome: TrashOutcome.Opened } : describeFailure(result);
}

/**
 * Counts the items in the Trash, shows the confirmation when there are any, and empties the Trash
 * only when the confirmation printed `CONFIRMED_REPLY`.
 */
export async function emptyTrashAfterConfirmation(
  runAppleScript: AppleScriptRunner,
): Promise<TrashCommandResult> {
  const counting = await runAppleScript(COUNT_TRASH_ITEMS_SCRIPT);
  if (!hasSucceeded(counting)) {
    return describeFailure(counting);
  }
  const countText = counting.stdout.trim();
  if (!/^\d+$/.test(countText)) {
    return {
      outcome: TrashOutcome.Failed,
      failure: `the Finder gave "${countText}" as the number of items in the Trash`,
    };
  }
  if (Number(countText) === 0) {
    return { outcome: TrashOutcome.TrashWasEmpty };
  }

  const confirmation = await runAppleScript(CONFIRMATION_SCRIPT);
  if (!hasSucceeded(confirmation)) {
    return describeFailure(confirmation);
  }
  if (confirmation.stdout.trim() !== CONFIRMED_REPLY) {
    return { outcome: TrashOutcome.Cancelled };
  }

  const emptying = await runAppleScript(EMPTY_TRASH_SCRIPT);
  return hasSucceeded(emptying) ? { outcome: TrashOutcome.Emptied } : describeFailure(emptying);
}

const TRASH_COMMANDS: Readonly<
  Record<string, (runAppleScript: AppleScriptRunner) => Promise<TrashCommandResult>>
> = {
  'open-trash': openTrash,
  'empty-trash': emptyTrashAfterConfirmation,
};

export function findTrashCommand(
  commandId: string,
): ((runAppleScript: AppleScriptRunner) => Promise<TrashCommandResult>) | null {
  return Object.hasOwn(TRASH_COMMANDS, commandId) ? TRASH_COMMANDS[commandId] : null;
}

/** The notification for a result that the user does not see in the Finder, or null. */
export function buildResultNotification(
  commandName: string,
  result: TrashCommandResult,
): NotificationOptions | null {
  switch (result.outcome) {
    case TrashOutcome.TrashWasEmpty:
      return { title: commandName, body: 'The Trash is empty.' };
    case TrashOutcome.Failed:
      return { title: `${commandName} failed`, body: result.failure };
    default:
      return null;
  }
}
