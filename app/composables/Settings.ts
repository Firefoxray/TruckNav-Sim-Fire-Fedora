import type { GameType } from "~/types";

export type UnitSystem = "metric" | "imperial";
export type TextTheme = "light" | "dark";
export type UiComponent =
    | "speed"
    | "fuel"
    | "sleep"
    | "time"
    | "speedLimit"
    | "topBar";
export type ActiveComponents = UiComponent[];
export type LocaleCode = "en" | "de" | "nl" | "cs" | "sk" | "ko" | "ro";

export interface MapLayerVisibility {
    poiIcons: boolean;
    roadIcons: boolean;
    cityLabels: boolean;
    regionLabels: boolean;
    facilityAreas: boolean;
}

export interface GameProfile {
    themeColor: string;
    textColor: TextTheme;
    routeColor: string;
    backgroundColor: string;
    landColor: string;
    roadColor: string;
    units: UnitSystem;
    ownedDlcs: number[];
    lastDestination: [number, number] | null;
    hasTurnNavigation: boolean;
    fontFamily: string;
    activeMod: string | "none";
    mapLayers: MapLayerVisibility;
}

export interface AppSettingsState {
    selectedGame: GameType;
    savedIP: string | null;
    profiles: {
        ets2: GameProfile;
        ats: GameProfile;
    };
    hudBtnSize: number;
    truckMarkerSize: number;
    compactTripFontSize: number;
    startOnMap: boolean;
    activeUiComponents: ActiveComponents;
    locale: LocaleCode;
}

interface SharedSettingsResponse {
    revision: number;
    updatedAt?: string;
    settings: Partial<AppSettingsState> | null;
}

const DEFAULT_MAP_LAYERS: MapLayerVisibility = {
    poiIcons: true,
    roadIcons: true,
    cityLabels: true,
    regionLabels: true,
    facilityAreas: true,
};

const DEFAULT_PROFILE: GameProfile = {
    themeColor: "#fbc02d",
    textColor: "light",
    routeColor: "#22d3ee",
    roadColor: "#4a5f7a",
    backgroundColor: "#24467b",
    landColor: "#272d39",
    units: "metric",
    ownedDlcs: Array.from({ length: 10 }, (_, i) => i + 1),
    lastDestination: null,
    hasTurnNavigation: true,
    fontFamily: "Commissioner",
    activeMod: "none",
    mapLayers: { ...DEFAULT_MAP_LAYERS },
};

const DEFAULT_SETTINGS: AppSettingsState = {
    selectedGame: null,
    savedIP: null,
    profiles: {
        ets2: {
            ...DEFAULT_PROFILE,
            themeColor: "#fbc02d",
            textColor: "dark",
            units: "metric",
        },
        ats: {
            ...DEFAULT_PROFILE,
            themeColor: "#d32f2f",
            ownedDlcs: Array.from({ length: 18 }, (_, i) => i + 1),
            units: "imperial",
        },
    },
    hudBtnSize: 30,
    truckMarkerSize: 40,
    compactTripFontSize: 1.8,
    startOnMap: false,
    activeUiComponents: [
        "speed",
        "speedLimit",
        "fuel",
        "time",
        "sleep",
        "topBar",
    ],
    locale: "en",
};

const STORAGE_KEY = "truck-nav-settings";
const SHARED_SETTINGS_URL = "/api/linux/settings";
const SHARED_POLL_MS = 1500;

let sharedRevision = 0;
let sharedSaveTimer: ReturnType<typeof setTimeout> | null = null;
let sharedPollTimer: ReturnType<typeof setInterval> | null = null;
let applyingSharedSettings = false;
let initPromise: Promise<void> | null = null;

function cloneDefaults(): AppSettingsState {
    return JSON.parse(JSON.stringify(DEFAULT_SETTINGS));
}

function mergeSettings(
    raw: Partial<AppSettingsState> | null | undefined,
    current?: AppSettingsState,
): AppSettingsState {
    const defaults = cloneDefaults();
    const source = raw || {};

    const merged: AppSettingsState = {
        ...defaults,
        ...source,
        profiles: {
            ets2: {
                ...defaults.profiles.ets2,
                ...(source.profiles?.ets2 || {}),
                mapLayers: {
                    ...defaults.profiles.ets2.mapLayers,
                    ...(source.profiles?.ets2?.mapLayers || {}),
                },
            },
            ats: {
                ...defaults.profiles.ats,
                ...(source.profiles?.ats || {}),
                mapLayers: {
                    ...defaults.profiles.ats.mapLayers,
                    ...(source.profiles?.ats?.mapLayers || {}),
                },
            },
        },
    };

    // Route destinations are session/navigation state, not a shared preference.
    // Keep each browser's active destination independent.
    if (current) {
        merged.profiles.ets2.lastDestination =
            current.profiles.ets2.lastDestination;
        merged.profiles.ats.lastDestination =
            current.profiles.ats.lastDestination;
    }

    return merged;
}

function toSharedSettings(settings: AppSettingsState): AppSettingsState {
    const shared = JSON.parse(JSON.stringify(settings)) as AppSettingsState;
    shared.profiles.ets2.lastDestination = null;
    shared.profiles.ats.lastDestination = null;
    return shared;
}

function canUseSharedWebSettings(): boolean {
    if (typeof window === "undefined") return false;
    if ((window as any).electronAPI) return false;
    return window.location.protocol === "http:" || window.location.protocol === "https:";
}

export const useSettings = () => {
    const settings = useState<AppSettingsState>("app-settings", () =>
        cloneDefaults(),
    );

    const activeSettings = computed(() => {
        const game = settings.value.selectedGame || "ets2";
        return settings.value.profiles[game];
    });

    const applySideEffects = () => {
        if (typeof document === "undefined") return;

        document.documentElement.style.setProperty(
            "--theme-color",
            activeSettings.value.themeColor,
        );

        const isLight = activeSettings.value.textColor === "light";

        document.documentElement.style.setProperty(
            "--main-text-color",
            isLight ? "#f2f2f2" : "#333",
        );

        document.documentElement.style.setProperty(
            "--app-font",
            activeSettings.value.fontFamily,
        );

        document.documentElement.style.setProperty(
            "--hud-btn-size",
            `${settings.value.hudBtnSize}px`,
        );

        document.documentElement.style.setProperty(
            "--compact-trip-size",
            `${settings.value.compactTripFontSize}rem`,
        );

        document.documentElement.style.setProperty(
            "--top-bar-height",
            !settings.value.activeUiComponents.includes("topBar")
                ? "0px"
                : "40px",
        );
    };

    const saveLocalSettings = () => {
        if (typeof localStorage === "undefined") return;
        localStorage.setItem(STORAGE_KEY, JSON.stringify(settings.value));
    };

    const persistSharedSettings = async () => {
        if (!canUseSharedWebSettings() || applyingSharedSettings) return;

        try {
            const response = await fetch(SHARED_SETTINGS_URL, {
                method: "PUT",
                headers: {
                    "content-type": "application/json",
                },
                body: JSON.stringify({
                    settings: toSharedSettings(settings.value),
                }),
            });

            if (!response.ok) {
                throw new Error(
                    `shared settings save failed: ${response.status}`,
                );
            }

            const result = await response.json();
            if (typeof result?.revision === "number") {
                sharedRevision = Math.max(
                    sharedRevision,
                    result.revision,
                );
            }
        } catch (error) {
            console.warn("Could not save shared TruckNav settings:", error);
        }
    };

    const queueSharedSave = () => {
        if (!canUseSharedWebSettings() || applyingSharedSettings) return;

        if (sharedSaveTimer) clearTimeout(sharedSaveTimer);
        sharedSaveTimer = setTimeout(() => {
            sharedSaveTimer = null;
            void persistSharedSettings();
        }, 180);
    };

    const saveSettings = () => {
        saveLocalSettings();
        applySideEffects();
        queueSharedSave();
    };

    const applySharedPayload = (payload: SharedSettingsResponse) => {
        if (!payload.settings || payload.revision <= sharedRevision) return;

        applyingSharedSettings = true;
        try {
            settings.value = mergeSettings(
                payload.settings,
                settings.value,
            );
            sharedRevision = payload.revision;
            saveLocalSettings();
            applySideEffects();
        } finally {
            applyingSharedSettings = false;
        }
    };

    const fetchSharedSettings = async (): Promise<SharedSettingsResponse | null> => {
        if (!canUseSharedWebSettings()) return null;

        try {
            const response = await fetch(SHARED_SETTINGS_URL, {
                cache: "no-store",
            });
            if (!response.ok) return null;
            return (await response.json()) as SharedSettingsResponse;
        } catch (error) {
            console.warn("Could not load shared TruckNav settings:", error);
            return null;
        }
    };

    const startSharedSettingsSync = () => {
        if (!canUseSharedWebSettings() || sharedPollTimer) return;

        sharedPollTimer = setInterval(async () => {
            const payload = await fetchSharedSettings();
            if (payload) applySharedPayload(payload);
        }, SHARED_POLL_MS);
    };

    const updateGlobal = <K extends keyof Omit<AppSettingsState, "profiles">>(
        key: K,
        value: AppSettingsState[K],
    ) => {
        settings.value[key] = value;
        saveSettings();
    };

    const updateProfile = <K extends keyof GameProfile>(
        key: K,
        value: GameProfile[K],
    ) => {
        const game = settings.value.selectedGame || "ets2";
        settings.value.profiles[game][key] = value;
        saveSettings();
    };

    const initSettings = async () => {
        if (initPromise) return initPromise;

        initPromise = (async () => {
            let localSettings: Partial<AppSettingsState> | null = null;

            if (typeof localStorage !== "undefined") {
                const savedString = localStorage.getItem(STORAGE_KEY);

                if (savedString) {
                    try {
                        localSettings = JSON.parse(savedString);
                    } catch (error) {
                        console.error(
                            "Corrupt local settings found, resetting to defaults.",
                            error,
                        );
                    }
                }
            }

            settings.value = mergeSettings(localSettings);
            applySideEffects();

            if (canUseSharedWebSettings()) {
                const shared = await fetchSharedSettings();

                if (shared?.settings) {
                    sharedRevision = shared.revision || 0;
                    applyingSharedSettings = true;
                    try {
                        settings.value = mergeSettings(
                            shared.settings,
                            settings.value,
                        );
                        saveLocalSettings();
                        applySideEffects();
                    } finally {
                        applyingSharedSettings = false;
                    }
                } else {
                    await persistSharedSettings();
                }

                startSharedSettingsSync();
            }
        })();

        try {
            await initPromise;
        } catch (error) {
            initPromise = null;
            throw error;
        }
    };

    const resetGlobalSetting = <
        K extends keyof Omit<AppSettingsState, "profiles">,
    >(
        key: K,
    ) => {
        settings.value[key] = cloneDefaults()[key];
        saveSettings();
    };

    const resetProfileSetting = <K extends keyof GameProfile>(key: K) => {
        const game = settings.value.selectedGame || "ets2";
        const defaultValue = cloneDefaults().profiles[game][key];

        settings.value.profiles[game][key] = defaultValue;
        saveSettings();
    };

    const resetSettings = () => {
        const game = settings.value.selectedGame || "ets2";

        const currentDest = settings.value.profiles[game].lastDestination;

        const freshProfile = cloneDefaults().profiles[game];
        freshProfile.lastDestination = currentDest;

        settings.value.hudBtnSize = DEFAULT_SETTINGS.hudBtnSize;
        settings.value.truckMarkerSize = DEFAULT_SETTINGS.truckMarkerSize;
        settings.value.compactTripFontSize =
            DEFAULT_SETTINGS.compactTripFontSize;
        settings.value.startOnMap = DEFAULT_SETTINGS.startOnMap;

        settings.value.activeUiComponents = [
            ...DEFAULT_SETTINGS.activeUiComponents,
        ];

        settings.value.profiles[game] = freshProfile;

        saveSettings();
    };

    return {
        settings,
        activeSettings,
        DEFAULT_SETTINGS,
        updateGlobal,
        updateProfile,
        resetGlobalSetting,
        resetProfileSetting,
        initSettings,
        resetSettings,
    };
};
