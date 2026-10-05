import {
    mkdirSync,
    renameSync,
    writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import {
    createError,
    defineEventHandler,
    readBody,
} from "h3";
import { canManageTruckNavHost } from "../../utils/trucknavAccess";

function settingsPath(): string {
    const configRoot =
        process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
    return join(configRoot, "trucknav-linux", "shared-settings.json");
}

export default defineEventHandler(async (event) => {
    if (!canManageTruckNavHost(event)) {
        throw createError({
            statusCode: 403,
            statusMessage:
                "TruckNav settings can only be changed from the private LAN.",
        });
    }

    const body = await readBody<{ settings?: unknown }>(event);

    if (
        !body ||
        !body.settings ||
        typeof body.settings !== "object" ||
        Array.isArray(body.settings)
    ) {
        throw createError({
            statusCode: 400,
            statusMessage: "TruckNav settings payload is invalid.",
        });
    }

    const serializedSettings = JSON.stringify(body.settings);
    if (serializedSettings.length > 256_000) {
        throw createError({
            statusCode: 413,
            statusMessage: "TruckNav settings payload is too large.",
        });
    }

    const path = settingsPath();
    const tmpPath = path + ".tmp";
    mkdirSync(dirname(path), { recursive: true });

    const payload = {
        revision: Date.now(),
        updatedAt: new Date().toISOString(),
        settings: body.settings,
    };

    writeFileSync(
        tmpPath,
        JSON.stringify(payload, null, 2) + "\n",
        {
            encoding: "utf8",
            mode: 0o600,
        },
    );
    renameSync(tmpPath, path);

    return {
        revision: payload.revision,
        updatedAt: payload.updatedAt,
    };
});
