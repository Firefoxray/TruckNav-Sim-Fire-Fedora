import { Capacitor } from "@capacitor/core";
import {
    getGameState,
    getJobState,
    getNavigationState,
    getTruckState,
} from "~/assets/utils/telemetry/helpers";
import type {
    TruckState,
    GameState,
    NavigationState,
    JobState,
    TelemetryUpdate,
    TelemetryPacket,
} from "~/types";

const truckState = reactive<TruckState>({
    truckCoords: [0, 0],
    truckHeading: 0,
    truckSpeed: 0,
    averageSpeed: 80,
});

const gameState = reactive<GameState>({
    gameTime: "",
    gameConnected: false,
    hasInGameMarker: false,
    scale: 0,
});

const navigationState = reactive<NavigationState>({
    fuel: 0,
    speedLimit: 0,
    restStoptime: "",
    restStopMinutes: 0,
});

const jobState = reactive<JobState>({
    hasActiveJob: false,
    income: 0,
    deadlineTime: new Date(),
    remainingTime: new Date(),
    sourceCity: "0",
    sourceCompany: "0",
    destinationCity: "0",
    destinationCompany: "0",
});

let lastPosition: [number, number] | null = null;
let headingOffset = 0;

let socket: WebSocket | null = null;
let relayPollTimer: ReturnType<typeof setInterval> | null = null;
let relayPollInFlight = false;
let lastRelaySuccessAt = 0;
let relayRequestController: AbortController | null = null;
let socketReconnectTimer: ReturnType<typeof setTimeout> | null = null;
// Invalidates responses and reconnect callbacks from previous map sessions.
let telemetryGeneration = 0;

const RELAY_POLL_INTERVAL_MS = 150;
const RELAY_REQUEST_TIMEOUT_MS = 2500;
const RELAY_DISCONNECT_GRACE_MS = 3000;

function sendDiscordRpcState(payload: {
    game: string;
    connected: boolean;
    hasActiveJob: boolean;
    sourceCity?: string;
    destinationCity?: string;
    cargoName?: string;
    truckBrand?: string;
    truckName?: string;
}) {
    if (typeof window === "undefined") return;

    const electronApi = (window as any).electronAPI;
    if (!electronApi?.updateDiscordRpc) return;

    electronApi.updateDiscordRpc(payload);
}

function clearDiscordRpcState() {
    if (typeof window === "undefined") return;

    const electronApi = (window as any).electronAPI;
    if (!electronApi?.clearDiscordRpc) return;

    electronApi.clearDiscordRpc();
}

export function useEtsTelemetry() {
    const { settings } = useSettings();

    const isCapacitor = Capacitor.isNativePlatform();

    let speedSamples: number[] = [];
    const maxSamples = 120;

    function startTelemetry(onUpdate?: (data: TelemetryUpdate) => void) {
        const canUseServerRelay =
            !isCapacitor &&
            typeof window !== "undefined" &&
            (window.location.protocol === "http:" ||
                window.location.protocol === "https:");

        if (canUseServerRelay) {
            if (relayPollTimer) return;
            const generation = ++telemetryGeneration;

            const markDisconnectedIfStale = () => {
                if (generation !== telemetryGeneration) return;
                if (
                    lastRelaySuccessAt === 0 ||
                    Date.now() - lastRelaySuccessAt >= RELAY_DISCONNECT_GRACE_MS
                ) {
                    resetDataOnDisconnected(onUpdate);
                }
            };

            const pollRelay = async () => {
                if (relayPollInFlight || generation !== telemetryGeneration) return;
                relayPollInFlight = true;

                const controller = new AbortController();
                relayRequestController = controller;
                const timeout = setTimeout(
                    () => controller.abort(),
                    RELAY_REQUEST_TIMEOUT_MS,
                );

                try {
                    const response = await fetch("/api/telemetry", {
                        cache: "no-store",
                        signal: controller.signal,
                    });
                    if (generation !== telemetryGeneration) return;

                    if (!response.ok) {
                        markDisconnectedIfStale();
                        return;
                    }

                    const relay = await response.json();
                    if (generation !== telemetryGeneration) return;
                    if (!relay?.connected || !relay?.data) {
                        markDisconnectedIfStale();
                        return;
                    }

                    const data = relay.data as TelemetryPacket;
                    if (
                        data.game?.toLowerCase() !==
                        settings.value.selectedGame
                    ) {
                        resetDataOnDisconnected(onUpdate);
                        return;
                    }

                    lastRelaySuccessAt = Date.now();
                    processData(data, onUpdate);
                } catch {
                    // A brief LAN/Wi-Fi hiccup should not permanently wedge
                    // relayPollInFlight or instantly blank the HUD. The abort
                    // timeout guarantees this request settles and polling
                    // continues automatically.
                    markDisconnectedIfStale();
                } finally {
                    clearTimeout(timeout);
                    if (relayRequestController === controller) {
                        relayRequestController = null;
                    }
                    if (generation === telemetryGeneration) {
                        relayPollInFlight = false;
                    }
                }
            };

            lastRelaySuccessAt = 0;
            void pollRelay();
            relayPollTimer = setInterval(
                pollRelay,
                RELAY_POLL_INTERVAL_MS,
            );
            return;
        }

        if (socket) return;
        const generation = ++telemetryGeneration;
        if (socketReconnectTimer) {
            clearTimeout(socketReconnectTimer);
            socketReconnectTimer = null;
        }

        const ip = settings.value.savedIP || window.location.hostname;
        const url = `ws://${ip}:30001`;

        socket = new WebSocket(url);

        socket.onopen = () => {
            if (generation !== telemetryGeneration) return;
            console.log("Connected to Bridge");
        };

        socket.onmessage = (event) => {
            if (generation !== telemetryGeneration) return;
            try {
                const rawData = JSON.parse(event.data);

                const data = rawData as TelemetryPacket;

                if (data.game.toLowerCase() !== settings.value.selectedGame) {
                    resetDataOnDisconnected(onUpdate);
                    return;
                }

                if (data) {
                    processData(data, onUpdate);
                }
            } catch (e) {
                console.error("Data error", e);
            }
        };

        socket.onclose = () => {
            if (generation !== telemetryGeneration) return;
            socket = null;
            resetDataOnDisconnected(onUpdate);
            socketReconnectTimer = setTimeout(() => {
                socketReconnectTimer = null;
                if (generation === telemetryGeneration) startTelemetry(onUpdate);
            }, 3000);
        };
    }

    function stopTelemetry() {
        telemetryGeneration++;
        if (socketReconnectTimer) {
            clearTimeout(socketReconnectTimer);
            socketReconnectTimer = null;
        }
        if (relayRequestController) {
            relayRequestController.abort();
            relayRequestController = null;
        }
        if (relayPollTimer) {
            clearInterval(relayPollTimer);
            relayPollTimer = null;
        }
        relayPollInFlight = false;
        lastRelaySuccessAt = 0;

        if (socket) {
            socket.onclose = null;
            socket.close();
            socket = null;
        }
        resetDataOnDisconnected();
    }

    function processData(
        data: TelemetryPacket,
        onUpdate?: (data: TelemetryUpdate) => void,
    ) {
        const { gameConnected, hasInGameMarker, gameTime, scale } =
            getGameState(data);

        Object.assign(gameState, {
            gameTime: gameTime,
            gameConnected: gameConnected,
            hasInGameMarker: hasInGameMarker,
            scale: scale,
        });

        const {
            truckCoords,
            truckSpeed,
            truckHeading,
            headingOffset: newOffset,
            avgSpeed,
        } = getTruckState(
            data,
            lastPosition,
            settings.value.selectedGame,
            headingOffset,
            speedSamples,
            maxSamples,
        );

        Object.assign(truckState, {
            truckCoords: truckCoords,
            truckHeading: truckHeading,
            truckSpeed: truckSpeed,
            averageSpeed: avgSpeed,
        });

        lastPosition = truckCoords;
        headingOffset = newOffset;

        const { fuel, speedLimit, restStoptime, restStopMinutes } =
            getNavigationState(data);

        Object.assign(navigationState, {
            restStoptime: restStoptime,
            restStopMinutes: restStopMinutes,
            speedLimit: speedLimit,
            fuel: fuel,
        });

        const {
            hasActiveJob,
            cityTarget: destinationCity,
            companyTarget: destinationCompany,
        } = getJobState(data, settings.value.selectedGame);

        Object.assign(jobState, {
            hasActiveJob: hasActiveJob,
            destinationCity: destinationCity,
            destinationCompany: destinationCompany,
        });

        sendDiscordRpcState({
            game: data.game,
            connected: gameConnected,
            hasActiveJob,
            sourceCity: data.job.citySource || data.job.citySourceId,
            destinationCity:
                data.job.cityDestination || data.job.cityDestinationId,
            cargoName: data.job.cargo?.name,
            truckBrand: data.truck.constants?.brand,
            truckName: data.truck.constants?.name,
        });

        if (onUpdate) {
            onUpdate({
                truck: { ...truckState },
                game: { ...gameState },
                general: { ...navigationState },
                job: { ...jobState },
            });
        }
    }

    function resetDataOnDisconnected(
        onUpdate?: (data: TelemetryUpdate) => void,
    ) {
        const wasConnected = gameState.gameConnected;
        headingOffset = 0;
        lastPosition = null;
        speedSamples = [];

        Object.assign(gameState, {
            gameConnected: false,
            hasInGameMarker: false,
            gameTime: "",
            scale: 0,
        });

        Object.assign(truckState, {
            truckCoords: [0, 0],
            truckHeading: 0,
            truckSpeed: 0,
        });

        Object.assign(navigationState, {
            fuel: 0,
            speedLimit: 0,
            restStopMinutes: 0,
            restStoptime: "0",
        });

        Object.assign(jobState, {
            hasActiveJob: false,
        });

        clearDiscordRpcState();

        if (onUpdate && wasConnected) {
            onUpdate({
                truck: { ...truckState },
                game: { ...gameState },
                general: { ...navigationState },
                job: { ...jobState },
            });
        }
    }

    return {
        ...toRefs(navigationState),
        ...toRefs(truckState),
        ...toRefs(gameState),
        ...toRefs(jobState),
        startTelemetry,
        stopTelemetry,
    };
}
