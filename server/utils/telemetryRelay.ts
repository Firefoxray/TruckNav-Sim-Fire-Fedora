import WebSocket from "ws";

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let latestPacket: unknown = null;
let lastMessageAt = 0;
let started = false;

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
}

export function stopTelemetryRelay() {
    started = false;
    if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
    }
    if (socket) {
        socket.removeAllListeners();
        socket.close();
        socket = null;
    }
    latestPacket = null;
    lastMessageAt = 0;
}

export function getTelemetryRelayState() {
    const ageMs = lastMessageAt ? Date.now() - lastMessageAt : null;
    const fresh = ageMs !== null && ageMs < 5000;

    return {
        connected: socket?.readyState === WebSocket.OPEN && fresh,
        helperSocketOpen: socket?.readyState === WebSocket.OPEN,
        lastMessageAt: lastMessageAt || null,
        ageMs,
        data: fresh ? latestPacket : null,
    };
}
