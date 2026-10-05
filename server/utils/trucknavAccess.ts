import type { H3Event } from "h3";

function normalizeIp(raw: string | undefined | null): string {
    if (!raw) return "";
    const value = raw.trim();
    if (value.startsWith("::ffff:")) return value.slice(7);
    return value;
}

export function getTruckNavClientIp(event: H3Event): string {
    const socketIp = normalizeIp(event.node.req.socket.remoteAddress);
    const forwarded = event.node.req.headers["x-forwarded-for"];
    const firstForwarded = Array.isArray(forwarded)
        ? forwarded[0]
        : forwarded?.split(",")[0];

    return normalizeIp(firstForwarded) || socketIp || "unknown";
}

/**
 * TruckNav Linux is a personal/LAN application in this fork.
 *
 * By default every browser that can reach the TruckNav web application can
 * change shared settings and invoke host maintenance actions. This avoids
 * brittle client-IP/proxy detection for direct LAN IPs and trucknav.rayco.tech.
 *
 * If the service is ever exposed to an untrusted/public network, launch it with
 * TRUCKNAV_SHARED_ADMIN=0 to disable remote maintenance/settings writes until
 * authentication is added.
 */
export function canManageTruckNavHost(_event: H3Event): boolean {
    return process.env.TRUCKNAV_SHARED_ADMIN !== "0";
}
