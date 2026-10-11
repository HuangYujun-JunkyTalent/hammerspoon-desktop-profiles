import type { DynamicCommandRegistration } from 'asyar-sdk/contracts';

const URL_PREFIX = 'hammerspoon://desktop-manager?';
const PROFILE_COMMAND_PATTERN = /^profile-(\d+)$/;

/** The id of the manifest command that returns the application numbers to the default. */
export const REASSIGN_APP_NUMBERS_COMMAND_ID = 'reassign-app-numbers';

/** What the items show of the state file that the Hammerspoon desktop manager writes. */
export interface ProfileSummary {
  activeProfileNumber: number | null;
  nameByNumber: Map<number, string>;
}

const EMPTY_SUMMARY: ProfileSummary = { activeProfileNumber: null, nameByNumber: new Map() };

function isProfileNumber(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= 1;
}

/**
 * Reads the active profile and the names of the profiles from the text of the state file.
 * A missing or unreadable state gives no active profile and no names, so the items still show.
 */
export function readProfileSummary(stateText: string | null): ProfileSummary {
  if (stateText === null) {
    return EMPTY_SUMMARY;
  }
  let state: unknown;
  try {
    state = JSON.parse(stateText);
  } catch {
    return EMPTY_SUMMARY;
  }
  if (typeof state !== 'object' || state === null) {
    return EMPTY_SUMMARY;
  }
  const { active_profile_number: activeNumber, profiles } = state as {
    active_profile_number?: unknown;
    profiles?: unknown;
  };
  const nameByNumber = new Map<number, string>();
  if (typeof profiles === 'object' && profiles !== null) {
    for (const profile of Object.values(profiles)) {
      const { number, name } = (profile ?? {}) as { number?: unknown; name?: unknown };
      if (isProfileNumber(number) && typeof name === 'string' && name.trim() !== '') {
        nameByNumber.set(number, name);
      }
    }
  }
  return {
    activeProfileNumber: isProfileNumber(activeNumber) ? activeNumber : null,
    nameByNumber,
  };
}

/**
 * One item per profile, named after its number and the name that the user gave it.
 * The active profile carries a green dot and the label "Active profile", and Enter deactivates it.
 */
export function describeProfileCommands(
  summary: ProfileSummary,
  profileCount: number,
): DynamicCommandRegistration[] {
  const registrations: DynamicCommandRegistration[] = [];
  for (let number = 1; number <= profileCount; number += 1) {
    const defaultName = `Profile ${number}`;
    const name = summary.nameByNumber.get(number);
    const isActive = summary.activeProfileNumber === number;
    registrations.push({
      id: `profile-${number}`,
      name: name && name !== defaultName ? `${defaultName} · ${name}` : defaultName,
      description: isActive ? 'Active. Enter deactivates it.' : 'Enter activates it.',
      icon: isActive ? '🟢' : '⚪',
      typeLabel: isActive ? 'Active profile' : 'Desktop profile',
    });
  }
  return registrations;
}

/** The URL of the Hammerspoon desktop manager that a command opens, or null for an unknown id. */
export function findCommandUrl(commandId: string): string | null {
  if (commandId === REASSIGN_APP_NUMBERS_COMMAND_ID) {
    return `${URL_PREFIX}action=reset-app-numbers`;
  }
  const match = PROFILE_COMMAND_PATTERN.exec(commandId);
  if (!match) {
    return null;
  }
  return `${URL_PREFIX}action=toggle&profile=${match[1]}`;
}
