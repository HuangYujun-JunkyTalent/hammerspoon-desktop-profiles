import { describe, expect, it } from 'vitest';
import manifest from '../manifest.json';
import {
  EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT,
  EMPTY_TRASH_CONFIRMATION,
  OPEN_TRASH_SCRIPT,
  OSASCRIPT_PATH,
  TRASH_IS_EMPTY_NOTICE,
  buildFailureNotification,
  buildOsascriptSpawn,
  findTrashCommandScript,
  quoteAppleScriptString,
} from './trash-commands';

/** The lines of a script without its quoted strings, so that a button label matches no command. */
function codeOf(scriptLines: readonly string[]): string[] {
  return scriptLines.map((line) => line.replace(/"(?:[^"\\]|\\.)*"/g, '""'));
}

/** The index of the one line of `code` that equals `line` after its indent, or a failed test. */
function indexOfLine(code: readonly string[], line: string): number {
  const indexes = code.flatMap((codeLine, index) => (codeLine.trim() === line ? [index] : []));
  expect(indexes, `the script holds the line "${line}" once`).toHaveLength(1);
  return indexes[0];
}

/** The depth of the indent of a line, in tabs. */
function depthOf(line: string): number {
  return line.length - line.trimStart().length;
}

describe('EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT', () => {
  const script = EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT.join('\n');
  const code = codeOf(EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT);

  it('reads each text from the strings of the Finder, with the English text as fallback', () => {
    for (const finderString of Object.values(EMPTY_TRASH_CONFIRMATION)) {
      const key = quoteAppleScriptString(finderString.key);
      expect(script).toContain(`localized string ${key} from table "LocalizableMerged"`);
      expect(script).toContain(`is ${key} then set`);
      expect(script).toContain(quoteAppleScriptString(finderString.english));
    }
    expect(script).toContain('POSIX file "/System/Library/CoreServices/Finder.app"');
  });

  it('counts the items first, and stops with a notification when the Trash is empty', () => {
    const count = indexOfLine(
      code,
      'tell application "" to set itemCount to count of items of trash',
    );
    const emptyCheck = indexOfLine(code, 'if itemCount is 0 then');
    const alert = code.findIndex((line) => line.includes('display alert'));
    expect(count).toBeLessThan(emptyCheck);
    expect(emptyCheck).toBeLessThan(alert);
    expect(EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT[emptyCheck + 1].trim()).toBe(
      `display notification ${quoteAppleScriptString(TRASH_IS_EMPTY_NOTICE)} with title "Empty Trash"`,
    );
    expect(code[emptyCheck + 2].trim()).toBe('return');
  });

  it('shows the alert in the Finder, with Cancel left of the default Empty Trash', () => {
    expect(script).toContain(
      'display alert messageText message informativeText ' +
        'buttons {cancelLabel, emptyLabel} default button emptyLabel cancel button cancelLabel',
    );
    const alert = code.findIndex((line) => line.includes('display alert'));
    const finderBlock = code.lastIndexOf('\ttell application ""', alert);
    expect(finderBlock).toBeGreaterThan(-1);
    expect(code[finderBlock + 1].trim()).toBe('activate');
  });

  it('empties only inside the branch of the button that empties', () => {
    const branch = indexOfLine(code, 'if button returned of alertReply is emptyLabel then');
    const branchEnd = code.findIndex(
      (line, index) =>
        index > branch &&
        line.trim() === 'end if' &&
        depthOf(line) === depthOf(code[branch]),
    );
    const empty = indexOfLine(code, 'empty trash');
    expect(empty).toBeGreaterThan(branch);
    expect(empty).toBeLessThan(branchEnd);
    const erasingLines = code.filter((line) => /\b(empty trash|delete)\b/.test(line));
    expect(erasingLines).toEqual([code[empty]]);
  });

  it('erases nothing after Cancel or Escape, which raise the error that the script ignores', () => {
    const alert = code.findIndex((line) => line.includes('display alert'));
    const empty = indexOfLine(code, 'empty trash');
    expect(alert).toBeLessThan(empty);
    expect(script).toContain('cancel button cancelLabel');
    expect(script).toContain(
      'if errorNumber is not -128 then display notification errorMessage with title "Empty Trash failed"',
    );
    expect(code.filter((line) => line.includes('on error number -128'))).toEqual([]);
  });

  it('turns off the warning of the Finder before the empty, so one confirmation shows', () => {
    const turnOff = indexOfLine(code, 'set warns before emptying of trash to false');
    const empty = indexOfLine(code, 'empty trash');
    expect(empty).toBeGreaterThan(turnOff);
  });

  it('restores the warning of the user after the empty and after an error of the empty', () => {
    const restores = code.flatMap((line, index) =>
      line.trim() === 'set warns before emptying of trash to warnsBeforeEmptying' ? [index] : [],
    );
    expect(restores).toHaveLength(2);
    const onError = indexOfLine(code, 'on error emptyErrorMessage number emptyErrorNumber');
    const raiseAgain = indexOfLine(code, 'error emptyErrorMessage number emptyErrorNumber');
    expect(restores[0]).toBeGreaterThan(onError);
    expect(restores[0]).toBeLessThan(raiseAgain);
    expect(restores[1]).toBeGreaterThan(raiseAgain);
  });

  it('runs every step inside the try that reports a failure as a notification', () => {
    const outerTry = code.findIndex((line) => line === 'try');
    const count = indexOfLine(
      code,
      'tell application "" to set itemCount to count of items of trash',
    );
    expect(outerTry).toBeGreaterThan(-1);
    expect(outerTry).toBeLessThan(count);
    expect(code.at(-1)).toBe('end try');
    expect(code.at(-3)).toBe('on error errorMessage number errorNumber');
  });
});

describe('OPEN_TRASH_SCRIPT', () => {
  it('opens the Trash in a window of the Finder, and reports a failure as a notification', () => {
    expect(OPEN_TRASH_SCRIPT).toEqual([
      'try',
      '\ttell application "Finder"',
      '\t\tactivate',
      '\t\topen trash',
      '\tend tell',
      'on error errorMessage number errorNumber',
      '\tif errorNumber is not -128 then display notification errorMessage with title "Trash failed"',
      'end try',
    ]);
  });

  it('erases nothing', () => {
    expect(codeOf(OPEN_TRASH_SCRIPT).join('\n')).not.toMatch(/\b(empty|delete)\b/);
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

describe('findTrashCommandScript', () => {
  it('gives a script for every command of the manifest', () => {
    for (const command of manifest.commands) {
      expect(findTrashCommandScript(command.id)).not.toBeNull();
    }
    expect(findTrashCommandScript('trash')).toBe(OPEN_TRASH_SCRIPT);
    expect(findTrashCommandScript('empty-trash')).toBe(EMPTY_TRASH_AFTER_CONFIRMATION_SCRIPT);
  });

  it('gives null for another id', () => {
    expect(findTrashCommandScript('open-trash')).toBeNull();
    expect(findTrashCommandScript('toString')).toBeNull();
  });
});

describe('the manifest', () => {
  it('names the command that opens the Trash Trash, with the id trash', () => {
    expect(manifest.commands.map((command) => [command.id, command.name])).toEqual([
      ['trash', 'Trash'],
      ['empty-trash', 'Empty Trash'],
    ]);
  });
});

describe('buildFailureNotification', () => {
  it('reports a failure with its reason', () => {
    expect(buildFailureNotification('Trash', 'SPAWN_FAILED: not trusted')).toEqual({
      title: 'Trash failed',
      body: 'SPAWN_FAILED: not trusted',
    });
  });
});
