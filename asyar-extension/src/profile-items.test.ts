import { describe, expect, it } from 'vitest';
import {
  describeProfileCommands,
  findCommandUrl,
  readProfileSummary,
  REASSIGN_APP_NUMBERS_COMMAND_ID,
} from './profile-items';

const STATE_TEXT = JSON.stringify({
  format_version: 1,
  monitor_matching: 'by_count',
  active_profile_number: 2,
  profiles: {
    '0': { number: 0, name: 'Profile 0', arrangements: {}, app_numbers: [] },
    '2': { number: 2, name: 'Writing', arrangements: {}, app_numbers: [] },
    '3': { number: 3, name: 'Profile 3', arrangements: {}, app_numbers: [] },
  },
});

describe('readProfileSummary', () => {
  it('reads the active profile and the names of the profiles', () => {
    const summary = readProfileSummary(STATE_TEXT);
    expect(summary.activeProfileNumber).toBe(2);
    expect(summary.nameByNumber.get(2)).toBe('Writing');
    expect(summary.nameByNumber.has(0)).toBe(false);
  });

  it('gives no active profile for a missing or broken state', () => {
    expect(readProfileSummary(null).activeProfileNumber).toBeNull();
    expect(readProfileSummary('{').activeProfileNumber).toBeNull();
    expect(readProfileSummary('[]').nameByNumber.size).toBe(0);
  });
});

describe('describeProfileCommands', () => {
  it('marks the active profile and names the renamed ones', () => {
    const commands = describeProfileCommands(readProfileSummary(STATE_TEXT), 9);
    expect(commands).toHaveLength(9);
    expect(commands[1]).toEqual({
      id: 'profile-2',
      name: 'Profile 2 · Writing',
      description: 'Active. Enter deactivates it.',
      icon: '🟢',
      typeLabel: 'Active profile',
    });
    expect(commands[2].name).toBe('Profile 3');
    expect(commands[2].icon).toBe('⚪');
    expect(commands.filter((command) => command.icon === '🟢')).toHaveLength(1);
  });

  it('marks no profile while none is active', () => {
    const commands = describeProfileCommands(readProfileSummary(null), 9);
    expect(commands.every((command) => command.typeLabel === 'Desktop profile')).toBe(true);
  });
});

describe('findCommandUrl', () => {
  it('toggles a profile and resets the application numbers', () => {
    expect(findCommandUrl('profile-4', 'desktop-manager')).toBe(
      'hammerspoon://desktop-manager?action=toggle&profile=4',
    );
    expect(findCommandUrl(REASSIGN_APP_NUMBERS_COMMAND_ID, 'desktop-manager')).toBe(
      'hammerspoon://desktop-manager?action=reset-app-numbers',
    );
    expect(findCommandUrl('profile-x', 'desktop-manager')).toBeNull();
  });

  it('opens the URLs of the setting url_event_name', () => {
    expect(findCommandUrl('profile-4', 'desktops')).toBe(
      'hammerspoon://desktops?action=toggle&profile=4',
    );
    expect(findCommandUrl(REASSIGN_APP_NUMBERS_COMMAND_ID, 'desktops')).toBe(
      'hammerspoon://desktops?action=reset-app-numbers',
    );
  });
});
