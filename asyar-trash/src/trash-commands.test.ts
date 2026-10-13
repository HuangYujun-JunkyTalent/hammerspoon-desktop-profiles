import { describe, expect, it } from 'vitest';
import manifest from '../manifest.json';
import {
  type AppleScriptResult,
  CANCELLED_REPLY,
  CONFIRMATION_SCRIPT,
  CONFIRMED_REPLY,
  COUNT_TRASH_ITEMS_SCRIPT,
  EMPTY_TRASH_CONFIRMATION,
  EMPTY_TRASH_SCRIPT,
  OPEN_TRASH_SCRIPT,
  OSASCRIPT_PATH,
  TrashOutcome,
  buildOsascriptSpawn,
  buildResultNotification,
  emptyTrashAfterConfirmation,
  findTrashCommand,
  openTrash,
  quoteAppleScriptString,
} from './trash-commands';

const SUCCESS = (stdout: string): AppleScriptResult => ({ exitCode: 0, stdout, stderr: '' });

/** A runner that answers each script with a fixed result and records the scripts in order. */
function recordScripts(answers: Map<readonly string[], AppleScriptResult>) {
  const scriptsRun: (readonly string[])[] = [];
  const runAppleScript = async (scriptLines: readonly string[]): Promise<AppleScriptResult> => {
    scriptsRun.push(scriptLines);
    const answer = answers.get(scriptLines);
    if (!answer) {
      throw new Error(`no answer for the script ${scriptLines.join(' / ')}`);
    }
    return answer;
  };
  return { scriptsRun, runAppleScript };
}

/** The lines of a script without its quoted strings, so that a button label matches no command. */
function codeOf(scriptLines: readonly string[]): string[] {
  return scriptLines.map((line) => line.replace(/"(?:[^"\\]|\\.)*"/g, '""'));
}

describe('emptyTrashAfterConfirmation', () => {
  it('empties the Trash after the confirmation prints the reply that empties', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([
        [COUNT_TRASH_ITEMS_SCRIPT, SUCCESS('3')],
        [CONFIRMATION_SCRIPT, SUCCESS(CONFIRMED_REPLY)],
        [EMPTY_TRASH_SCRIPT, SUCCESS('')],
      ]),
    );
    expect(await emptyTrashAfterConfirmation(runAppleScript)).toEqual({
      outcome: TrashOutcome.Emptied,
    });
    expect(scriptsRun).toEqual([COUNT_TRASH_ITEMS_SCRIPT, CONFIRMATION_SCRIPT, EMPTY_TRASH_SCRIPT]);
  });

  it('erases nothing after Cancel or Escape', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([
        [COUNT_TRASH_ITEMS_SCRIPT, SUCCESS('3')],
        [CONFIRMATION_SCRIPT, SUCCESS(CANCELLED_REPLY)],
      ]),
    );
    expect(await emptyTrashAfterConfirmation(runAppleScript)).toEqual({
      outcome: TrashOutcome.Cancelled,
    });
    expect(scriptsRun).not.toContain(EMPTY_TRASH_SCRIPT);
  });

  it('erases nothing when the confirmation prints another reply', async () => {
    for (const reply of ['', 'Empty Trash', `${CONFIRMED_REPLY} later`]) {
      const { scriptsRun, runAppleScript } = recordScripts(
        new Map([
          [COUNT_TRASH_ITEMS_SCRIPT, SUCCESS('1')],
          [CONFIRMATION_SCRIPT, SUCCESS(reply)],
        ]),
      );
      expect((await emptyTrashAfterConfirmation(runAppleScript)).outcome).toBe(
        TrashOutcome.Cancelled,
      );
      expect(scriptsRun).not.toContain(EMPTY_TRASH_SCRIPT);
    }
  });

  it('erases nothing when the confirmation fails', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([
        [COUNT_TRASH_ITEMS_SCRIPT, SUCCESS('2')],
        [
          CONFIRMATION_SCRIPT,
          { exitCode: 1, stdout: CONFIRMED_REPLY, stderr: 'execution error: (-1743)' },
        ],
      ]),
    );
    expect(await emptyTrashAfterConfirmation(runAppleScript)).toEqual({
      outcome: TrashOutcome.Failed,
      failure: 'execution error: (-1743)',
    });
    expect(scriptsRun).not.toContain(EMPTY_TRASH_SCRIPT);
  });

  it('erases nothing when osascript does not start', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([
        [
          COUNT_TRASH_ITEMS_SCRIPT,
          { stdout: '', stderr: '', spawnError: 'SPAWN_FAILED: the binary is not trusted' },
        ],
      ]),
    );
    expect(await emptyTrashAfterConfirmation(runAppleScript)).toEqual({
      outcome: TrashOutcome.Failed,
      failure: 'SPAWN_FAILED: the binary is not trusted',
    });
    expect(scriptsRun).toEqual([COUNT_TRASH_ITEMS_SCRIPT]);
  });

  it('shows no confirmation and erases nothing when the Trash is empty', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([[COUNT_TRASH_ITEMS_SCRIPT, SUCCESS('0\n')]]),
    );
    expect(await emptyTrashAfterConfirmation(runAppleScript)).toEqual({
      outcome: TrashOutcome.TrashWasEmpty,
    });
    expect(scriptsRun).toEqual([COUNT_TRASH_ITEMS_SCRIPT]);
  });

  it('shows no confirmation when the count of the Finder is not a number', async () => {
    for (const countText of ['', 'missing value', '-1']) {
      const { scriptsRun, runAppleScript } = recordScripts(
        new Map([[COUNT_TRASH_ITEMS_SCRIPT, SUCCESS(countText)]]),
      );
      expect((await emptyTrashAfterConfirmation(runAppleScript)).outcome).toBe(TrashOutcome.Failed);
      expect(scriptsRun).toEqual([COUNT_TRASH_ITEMS_SCRIPT]);
    }
  });
});

describe('CONFIRMATION_SCRIPT', () => {
  const script = CONFIRMATION_SCRIPT.join('\n');

  it('reads each text from the strings of the Finder, with the English text as fallback', () => {
    for (const finderString of Object.values(EMPTY_TRASH_CONFIRMATION)) {
      const key = quoteAppleScriptString(finderString.key);
      expect(script).toContain(`localized string ${key} from table "LocalizableMerged"`);
      expect(script).toContain(`is ${key} then set`);
      expect(script).toContain(quoteAppleScriptString(finderString.english));
    }
    expect(script).toContain('POSIX file "/System/Library/CoreServices/Finder.app"');
  });

  it('shows the alert in the Finder, with Cancel left of the default Empty Trash', () => {
    expect(script).toContain(
      'display alert messageText message informativeText ' +
        'buttons {cancelLabel, emptyLabel} default button emptyLabel cancel button cancelLabel',
    );
    expect(script.indexOf('tell application "Finder"')).toBeLessThan(
      script.indexOf('display alert'),
    );
  });

  it('prints the reply that empties for its button alone, and Cancel after Escape', () => {
    expect(script).toContain(
      `if button returned of alertReply is emptyLabel then return "${CONFIRMED_REPLY}"`,
    );
    expect(script).toMatch(/on error number -128\n\t\treturn "cancelled"/);
    expect(CONFIRMATION_SCRIPT.at(-1)).toBe(`return "${CANCELLED_REPLY}"`);
  });

  it('erases nothing itself', () => {
    expect(codeOf(CONFIRMATION_SCRIPT).join('\n')).not.toMatch(/\b(empty|delete)\b/);
    expect(codeOf(COUNT_TRASH_ITEMS_SCRIPT).join('\n')).not.toMatch(/\b(empty|delete)\b/);
    expect(codeOf(OPEN_TRASH_SCRIPT).join('\n')).not.toMatch(/\b(empty|delete)\b/);
  });
});

describe('EMPTY_TRASH_SCRIPT', () => {
  const code = codeOf(EMPTY_TRASH_SCRIPT);

  it('turns off the warning of the Finder before the empty, so one confirmation shows', () => {
    const turnOff = code.indexOf('\tset warns before emptying of trash to false');
    const empty = code.indexOf('\t\t\tempty trash');
    expect(turnOff).toBeGreaterThan(-1);
    expect(empty).toBeGreaterThan(turnOff);
  });

  it('restores the warning of the user after the empty and after an error', () => {
    const restores = code.filter(
      (line) => line.trim() === 'set warns before emptying of trash to warnsBeforeEmptying',
    );
    expect(restores).toHaveLength(2);
    expect(code.indexOf('\ton error errorMessage number errorNumber')).toBeLessThan(
      code.lastIndexOf('\t\terror errorMessage number errorNumber'),
    );
  });
});

describe('openTrash', () => {
  it('opens the Trash in a window of the Finder', async () => {
    const { scriptsRun, runAppleScript } = recordScripts(
      new Map([[OPEN_TRASH_SCRIPT, SUCCESS('')]]),
    );
    expect(await openTrash(runAppleScript)).toEqual({ outcome: TrashOutcome.Opened });
    expect(scriptsRun).toEqual([OPEN_TRASH_SCRIPT]);
    expect(OPEN_TRASH_SCRIPT).toContain('\topen trash');
  });
});

describe('buildOsascriptSpawn', () => {
  it('passes each line of the script to /usr/bin/osascript as one -e argument', () => {
    expect(buildOsascriptSpawn(['tell application "Finder"', '\topen trash', 'end tell'])).toEqual({
      program: OSASCRIPT_PATH,
      args: ['-e', 'tell application "Finder"', '-e', '\topen trash', '-e', 'end tell'],
    });
    expect(OSASCRIPT_PATH).toBe('/usr/bin/osascript');
  });
});

describe('quoteAppleScriptString', () => {
  it('escapes the backslash and the double quote', () => {
    expect(quoteAppleScriptString('a "b" \\ c')).toBe('"a \\"b\\" \\\\ c"');
  });
});

describe('findTrashCommand', () => {
  it('gives a command for every command of the manifest', () => {
    for (const command of manifest.commands) {
      expect(findTrashCommand(command.id)).not.toBeNull();
    }
    expect(findTrashCommand('open-trash')).toBe(openTrash);
    expect(findTrashCommand('empty-trash')).toBe(emptyTrashAfterConfirmation);
  });

  it('gives null for another id', () => {
    expect(findTrashCommand('tile-fill')).toBeNull();
    expect(findTrashCommand('toString')).toBeNull();
  });
});

describe('buildResultNotification', () => {
  it('tells the user that the Trash is empty', () => {
    expect(
      buildResultNotification('Empty Trash', { outcome: TrashOutcome.TrashWasEmpty }),
    ).toEqual({ title: 'Empty Trash', body: 'The Trash is empty.' });
  });

  it('reports a failure with its reason', () => {
    expect(
      buildResultNotification('Open Trash', {
        outcome: TrashOutcome.Failed,
        failure: 'execution error: (-1743)',
      }),
    ).toEqual({ title: 'Open Trash failed', body: 'execution error: (-1743)' });
  });

  it('sends nothing after the Finder has shown the result', () => {
    for (const outcome of [TrashOutcome.Opened, TrashOutcome.Emptied, TrashOutcome.Cancelled]) {
      expect(buildResultNotification('Empty Trash', { outcome })).toBeNull();
    }
  });
});
