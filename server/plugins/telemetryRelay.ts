import { defineNitroPlugin } from "#imports";
import {
    startTelemetryRelay,
    stopTelemetryRelay,
} from "../utils/telemetryRelay";

export default defineNitroPlugin((nitroApp) => {
    startTelemetryRelay();
    nitroApp.hooks.hook("close", () => {
        stopTelemetryRelay();
    });
});
