import {
    closeSync,
    existsSync,
    openSync,
    readFileSync,
    rmSync,
    writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import {
    createError,
    defineEventHandler,
    readBody,
} from "h3";
import {
    canManageTruckNavHost,
    getTruckNavClientIp,
} from "../../utils/trucknavAccess";

type LinuxAction = "update-app" | "rebuild-map";

function assertManageRequest(event: any) {
    if (!canManageTruckNavHost(event)) {
        throw createError({
            statusCode: 403,
            statusMessage:
                "TruckNav Linux maintenance actions are limited to the private LAN.",
        });
    }
}

function processAlive(pid: number): boolean {
    try {
        process.kill(pid, 0);
        return true;
    } catch {
        return false;
    }
}

export default defineEventHandler(async (event) => {
    assertManageRequest(event);

    const body = await readBody<{ action?: LinuxAction }>(event);
    const action = body?.action;

    if (action !== "update-app" && action !== "rebuild-map") {
        throw createError({
            statusCode: 400,
            statusMessage: "Unknown TruckNav Linux action.",
        });
    }

    const repoRoot = process.env.TRUCKNAV_REPO_ROOT || process.cwd();
    const statePath = join(tmpdir(), "trucknav-linux-job.json");
    const logPath = join(tmpdir(), "trucknav-linux-job.log");
    const exitPath = join(tmpdir(), "trucknav-linux-job.exit");

    if (existsSync(statePath) && !existsSync(exitPath)) {
        try {
            const previous = JSON.parse(readFileSync(statePath, "utf8"));
            if (
                typeof previous?.pid === "number" &&
                processAlive(previous.pid)
            ) {
                throw createError({
                    statusCode: 409,
                    statusMessage:
                        "Another TruckNav Linux maintenance job is already running.",
                });
            }
        } catch (error: any) {
            if (error?.statusCode === 409) throw error;
        }
    }

    rmSync(exitPath, { force: true });
    rmSync(logPath, { force: true });

    const relativeScript =
        action === "update-app"
            ? "scripts/linux/update-trucknav-linux.sh"
            : "scripts/map-data/rebuild-ats-trucknav-runtime.sh";

    const scriptPath = join(repoRoot, relativeScript);
    if (!existsSync(scriptPath)) {
        throw createError({
            statusCode: 500,
            statusMessage: "Maintenance script is missing: " + relativeScript,
        });
    }

    const logFd = openSync(logPath, "a");

    const wrapper = spawn(
        "bash",
        [
            "-c",
            'set +e; bash "$1"; code=$?; printf "%s\n" "$code" > "$2"; exit "$code"',
            "trucknav-linux-job",
            scriptPath,
            exitPath,
        ],
        {
            cwd: repoRoot,
            detached: true,
            stdio: ["ignore", logFd, logFd],
            env: {
                ...process.env,
                TRUCKNAV_REPO_ROOT: repoRoot,
            },
        },
    );

    closeSync(logFd);

    writeFileSync(
        statePath,
        JSON.stringify(
            {
                action,
                pid: wrapper.pid,
                startedAt: new Date().toISOString(),
            },
            null,
            2,
        ),
    );

    wrapper.unref();

    return {
        started: true,
        action,
        pid: wrapper.pid,
        clientIp: getTruckNavClientIp(event),
    };
});
