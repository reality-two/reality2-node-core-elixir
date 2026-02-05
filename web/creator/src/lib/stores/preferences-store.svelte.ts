// User preferences store with localStorage persistence
// Supports Standard/Advanced mode toggle for dual-audience UX

const STORAGE_KEY = "r2-preferences";

interface Preferences {
  advancedMode: boolean;
}

const defaultPreferences: Preferences = {
  advancedMode: false, // Default to Standard mode for simpler interface
};

function loadPreferences(): Preferences {
  if (typeof localStorage === "undefined") return defaultPreferences;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      return { ...defaultPreferences, ...JSON.parse(stored) };
    }
  } catch {
    // Invalid JSON, use defaults
  }
  return defaultPreferences;
}

function savePreferences(prefs: Preferences): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // Storage full or unavailable
  }
}

let preferences = $state<Preferences>(loadPreferences());

export function getAdvancedMode(): boolean {
  return preferences.advancedMode;
}

export function setAdvancedMode(value: boolean): void {
  preferences.advancedMode = value;
  savePreferences(preferences);
}

export function toggleAdvancedMode(): void {
  setAdvancedMode(!preferences.advancedMode);
}

export function isStandardMode(): boolean {
  return !preferences.advancedMode;
}
