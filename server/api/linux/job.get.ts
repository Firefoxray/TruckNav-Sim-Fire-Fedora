import {
    existsSync,
    readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defineEventHandler } from "h3";

function processAlive(pid: number): boolean {
    try {
        process.kill(pid, 0);
        return true;
    } catch {
        return false;
    }
}

export default defineEventHandler(() => {
    const statePath = join(tmpdir(), "trucknav-linux-job.json");
    const logPath = join(tmpdir(), "trucknav-linux-job.log");
    const exitPath = join(tmpdir(), "trucknav-linux-job.exit");

    if (!existsSync(statePath)) return null;

    let state: {
        action: "update-app" | "rebuild-map";
        game?: "ats" | "ets2" | null;
        pid: number;
        startedAt?: string;
    };

    try {
        state = JSON.parse(readFileSync(statePath, "utf8"));
    } catch {
        return null;
    }

    let exitCode: number | null = null;
    if (existsSync(exitPath)) {
        const parsed = Number(readFileSync(exitPath, "utf8").trim());
        exitCode = Number.isFinite(parsed) ? parsed : 1;
    }

    const running =
        exitCode == null &&
        typeof state.pid === "number" &&
        processAlive(state.pid);

    let logTail: string[] = [];
    if (existsSync(logPath)) {
        const lines = readFileSync(logPath, "utf8")
            .split(/\r?\n/)
            .filter(Boolean);
        logTail = lines.slice(-24);
    }

    return {
        action: state.action,
        game: state.game || null,
        running,
        exitCode: running ? null : exitCode ?? 1,
        startedAt: state.startedAt,
        logTail,
    };
});
