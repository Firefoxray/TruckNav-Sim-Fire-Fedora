import { defineEventHandler } from "h3";
import { getTelemetryRelayState } from "../utils/telemetryRelay";

export default defineEventHandler(() => {
    return getTelemetryRelayState();
});
