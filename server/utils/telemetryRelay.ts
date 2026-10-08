import WebSocket from "ws";

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let watchdogTimer: ReturnType<typeof setInterval> | null = null;
let latestPacket: any = null;
let lastMessageAt = 0;
let lastDataChangeAt = 0;
let lastPacketSignature = "";
let socketOpenedAt = 0;
let started = false;

const STALE_PACKET_MS = 5000;
const STALE_SOCKET_MS = 10000;
const STALE_DATA_MS = 12000;

function scheduleReconnect() {
    if (reconnectTimer) return;
    reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
    }, 2000);
}

function connect() {
    if (
        socket &&
        (socket.readyState === WebSocket.OPEN ||
            socket.readyState === WebSocket.CONNECTING)
    ) {
        return;
    }

    try {
        socket = new WebSocket("ws://127.0.0.1:30001");

        socket.on("open", () => {
            socketOpenedAt = Date.now();
        });

        socket.on("message", (message) => {
            try {
                const packet = JSON.parse(message.toString());
                const now = Date.now();

                const signature = [
                    packet?.paused ? 1 : 0,
                    packet?.common?.gameTime ?? "",
                    packet?.truck?.current?.position?.x ?? "",
                    packet?.truck?.current?.position?.z ?? "",
                    packet?.truck?.current?.dashboard?.odometer ?? "",
                    packet?.navigation?.distance ?? "",
                ].join("|");

                if (signature !== lastPacketSignature) {
                    lastPacketSignature = signature;
                    lastDataChangeAt = now;
                }

                latestPacket = packet;
                lastMessageAt = now;
            } catch {
                // Ignore malformed packets but keep the relay alive.
            }
        });

        socket.on("close", () => {
            socket = null;
            socketOpenedAt = 0;
            scheduleReconnect();
        });

        socket.on("error", () => {
            socket?.close();
        });
    } catch {
        socket = null;
        scheduleReconnect();
    }
}

export function startTelemetryRelay() {
    if (started) return;
    started = true;
    connect();

    watchdogTimer = setInterval(() => {
        if (!started || !socket || socket.readyState !== WebSocket.OPEN) return;

        const now = Date.now();
        const referenceTime = lastMessageAt || socketOpenedAt;
        if (!referenceTime) return;

        const messageStale = now - referenceTime > STALE_SOCKET_MS;
        const dataFrozen =
            latestPacket &&
            latestPacket.paused !== true &&
            lastDataChangeAt > 0 &&
            now - lastDataChangeAt > STALE_DATA_MS;

        if (messageStale || dataFrozen) {
            // A socket can stay OPEN while the helper stops delivering fresh
            // game state, including repeatedly broadcasting one frozen packet.
            // Force a reconnect so browsers do not keep displaying an old
            // truck position as if it were live.
            socket.terminate();
        }
    }, 2000);
}

export function stopTelemetryRelay() {
    started = false;
    if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
    }
    if (watchdogTimer) {
        clearInterval(watchdogTimer);
        watchdogTimer = null;
    }
    if (socket) {
        socket.removeAllListeners();
        socket.close();
        socket = null;
    }
    latestPacket = null;
    lastMessageAt = 0;
    lastDataChangeAt = 0;
    lastPacketSignature = "";
    socketOpenedAt = 0;
}

export function getTelemetryRelayState() {
    const now = Date.now();
    const ageMs = lastMessageAt ? now - lastMessageAt : null;
    const dataAgeMs = lastDataChangeAt ? now - lastDataChangeAt : null;
    const packetFresh = ageMs !== null && ageMs < STALE_PACKET_MS;
    const dataFresh =
        latestPacket?.paused === true ||
        (dataAgeMs !== null && dataAgeMs < STALE_DATA_MS);
    const fresh = packetFresh && dataFresh;

    return {
        connected: socket?.readyState === WebSocket.OPEN && fresh,
        helperSocketOpen: socket?.readyState === WebSocket.OPEN,
        lastMessageAt: lastMessageAt || null,
        lastDataChangeAt: lastDataChangeAt || null,
        ageMs,
        dataAgeMs,
        data: fresh ? latestPacket : null,
    };
}
