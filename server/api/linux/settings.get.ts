import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { defineEventHandler } from "h3";

function settingsPath(): string {
    const configRoot =
        process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
    return join(configRoot, "trucknav-linux", "shared-settings.json");
}

export default defineEventHandler(() => {
    const path = settingsPath();

    if (!existsSync(path)) {
        return {
            revision: 0,
            settings: null,
        };
    }

    try {
        const parsed = JSON.parse(readFileSync(path, "utf8"));
        if (
            parsed &&
            typeof parsed === "object" &&
            typeof parsed.revision === "number" &&
            parsed.settings &&
            typeof parsed.settings === "object"
        ) {
            return parsed;
        }
    } catch {
        // A bad file should not break TruckNav; a future write can repair it.
    }

    return {
        revision: 0,
        settings: null,
    };
});
