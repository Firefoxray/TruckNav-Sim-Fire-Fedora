import WebSocket from "ws";

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let watchdogTimer: ReturnType<typeof setInterval> | null = null;
let latestPacket: unknown = null;
let lastMessageAt = 0;
let socketOpenedAt = 0;
let started = false;

const STALE_PACKET_MS = 5000;
const STALE_SOCKET_MS = 10000;

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
                latestPacket = JSON.parse(message.toString());
                lastMessageAt = Date.now();
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

        const referenceTime = lastMessageAt || socketOpenedAt;
        if (!referenceTime) return;

        if (Date.now() - referenceTime > STALE_SOCKET_MS) {
            // A TCP/WebSocket can remain OPEN after the helper or network path
            // has effectively stopped delivering data. Terminating the stale
            // client forces the normal reconnect path instead of leaving
            // remote browsers permanently offline.
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
    socketOpenedAt = 0;
}

export function getTelemetryRelayState() {
    const ageMs = lastMessageAt ? Date.now() - lastMessageAt : null;
    const fresh = ageMs !== null && ageMs < STALE_PACKET_MS;

    return {
        connected: socket?.readyState === WebSocket.OPEN && fresh,
        helperSocketOpen: socket?.readyState === WebSocket.OPEN,
        lastMessageAt: lastMessageAt || null,
        ageMs,
        data: fresh ? latestPacket : null,
    };
}
