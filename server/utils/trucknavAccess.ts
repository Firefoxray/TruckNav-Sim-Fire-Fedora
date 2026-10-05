import type { H3Event } from "h3";

function normalizeIp(raw: string | undefined | null): string {
    if (!raw) return "";
    const value = raw.trim();
    if (value.startsWith("::ffff:")) return value.slice(7);
    return value;
}

function isPrivateIpv4(ip: string): boolean {
    const parts = ip.split(".").map(Number);
    if (
        parts.length !== 4 ||
        parts.some(part => !Number.isInteger(part) || part < 0 || part > 255)
    ) {
        return false;
    }

    if (parts[0] === 10) return true;
    if (parts[0] === 192 && parts[1] === 168) return true;
    if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;
    if (parts[0] === 127) return true;
    return false;
}

function isLoopback(ip: string): boolean {
    return ip === "::1" || ip === "127.0.0.1";
}

export function getTruckNavClientIp(event: H3Event): string {
    const socketIp = normalizeIp(event.node.req.socket.remoteAddress);

    // Trust proxy forwarding only when the HTTP connection itself comes from
    // loopback. This matches the local Caddy/reverse-proxy setup without
    // allowing an arbitrary remote client to spoof X-Forwarded-For.
    if (isLoopback(socketIp)) {
        const forwarded = event.node.req.headers["x-forwarded-for"];
        const firstForwarded = Array.isArray(forwarded)
            ? forwarded[0]
            : forwarded?.split(",")[0];

        const forwardedIp = normalizeIp(firstForwarded);
        if (forwardedIp) return forwardedIp;
    }

    return socketIp;
}

export function canManageTruckNavHost(event: H3Event): boolean {
    const ip = getTruckNavClientIp(event);
    return isLoopback(ip) || isPrivateIpv4(ip);
}
