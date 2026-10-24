import type { DynamicCommandRegistration } from 'asyar-sdk/contracts';

const PROFILE_COMMAND_PATTERN = /^profile-(\d+)$/;

/** The id of the manifest command that returns the application numbers to the default. */
export const REASSIGN_APP_NUMBERS_COMMAND_ID = 'reassign-app-numbers';

/** What the items show of the state file that the Hammerspoon desktop manager writes. */
export interface ProfileSummary {
  activeProfileNumber: number | null;
  isActiveProfilePaused: boolean;
  nameByNumber: Map<number, string>;
}

const EMPTY_SUMMARY: ProfileSummary = {
  activeProfileNumber: null,
  isActiveProfilePaused: false,
  nameByNumber: new Map(),
};

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
  const {
    active_profile_number: activeNumber,
    is_active_profile_paused: isPaused,
    profiles,
  } = state as {
    active_profile_number?: unknown;
    is_active_profile_paused?: unknown;
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
    isActiveProfilePaused: isProfileNumber(activeNumber) && isPaused === true,
    nameByNumber,
  };
}

const ACTIVE_LOOK = {
  description: 'Active. Enter deactivates it.',
  icon: '🟢',
  typeLabel: 'Active profile',
};
const PAUSED_LOOK = {
  description: 'Paused. Enter restores its layout.',
  icon: '🟡',
  typeLabel: 'Paused profile',
};
const INACTIVE_LOOK = {
  description: 'Enter activates it.',
  icon: '⚪',
  typeLabel: 'Desktop profile',
};

/**
 * One item per profile, named after its number and the name that the user gave it.
 * The active profile carries a green dot and the label "Active profile", and Enter deactivates it.
 * While the active profile is paused, it carries a yellow dot and the label "Paused profile", and
 * Enter restores its layout.
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
    const pausedOrActiveLook = summary.isActiveProfilePaused ? PAUSED_LOOK : ACTIVE_LOOK;
    registrations.push({
      id: `profile-${number}`,
      name: name && name !== defaultName ? `${defaultName} · ${name}` : defaultName,
      ...(isActive ? pausedOrActiveLook : INACTIVE_LOOK),
    });
  }
  return registrations;
}

/**
 * The URL of the Hammerspoon desktop manager that a command opens, or null for an unknown id.
 * The host of the URL is the setting `url_event_name` of the desktop manager.
 */
export function findCommandUrl(commandId: string, urlEventName: string): string | null {
  const urlPrefix = `hammerspoon://${urlEventName}?`;
  if (commandId === REASSIGN_APP_NUMBERS_COMMAND_ID) {
    return `${urlPrefix}action=reset-app-numbers`;
  }
  const match = PROFILE_COMMAND_PATTERN.exec(commandId);
  if (!match) {
    return null;
  }
  return `${urlPrefix}action=toggle&profile=${match[1]}`;
}
