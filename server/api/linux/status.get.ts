import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { defineEventHandler, getQuery } from "h3";
import {
    canManageTruckNavHost,
    getTruckNavClientIp,
} from "../../utils/trucknavAccess";

function git(repoRoot: string, args: string[]): string {
    return execFileSync("git", args, {
        cwd: repoRoot,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
    }).trim();
}

function readSteamInstallState(appId: string): {
    installedSteamBuildId: string | null;
    installedSteamLastUpdated: string | null;
} {
    const candidates = [
        join(
            process.env.HOME || "",
            ".local",
            "share",
            "Steam",
            "steamapps",
            `appmanifest_${appId}.acf`,
        ),
        join(
            process.env.HOME || "",
            ".steam",
            "steam",
            "steamapps",
            `appmanifest_${appId}.acf`,
        ),
    ];

    for (const manifestPath of candidates) {
        if (!existsSync(manifestPath)) continue;

        try {
            const text = readFileSync(manifestPath, "utf8");
            const buildMatch = text.match(/"buildid"\s+"([^"]+)"/);
            const updatedMatch = text.match(/"LastUpdated"\s+"([^"]+)"/);
            return {
                installedSteamBuildId: buildMatch?.[1] || null,
                installedSteamLastUpdated: updatedMatch?.[1] || null,
            };
        } catch {
            // Try the next common Steam location.
        }
    }

    return {
        installedSteamBuildId: null,
        installedSteamLastUpdated: null,
    };
}

export default defineEventHandler((event) => {
    const repoRoot = process.env.TRUCKNAV_REPO_ROOT || process.cwd();
    const query = getQuery(event);

    let branch = "unknown";
    let commit = "";

    let displayVersion = "dev";
    const versionPath = join(repoRoot, "VERSION");
    if (existsSync(versionPath)) {
        displayVersion =
            readFileSync(versionPath, "utf8").trim().replace(/^v/, "") ||
            "dev";
    } else {
        const packagePath = join(repoRoot, "package.json");
        if (existsSync(packagePath)) {
            try {
                const packageJson = JSON.parse(
                    readFileSync(packagePath, "utf8"),
                );
                displayVersion = String(packageJson?.version || "dev").replace(
                    /^v/,
                    "",
                );
            } catch {
                displayVersion = "dev";
            }
        }
    }

    if (/^\d+\.\d+\.0$/.test(displayVersion)) {
        displayVersion = displayVersion.replace(/\.0$/, "");
    }
    let upstream: string | null = null;
    let ahead = 0;
    let behind = 0;
    let fetchError: string | null = null;

    try {
        branch = git(repoRoot, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
    } catch {
        branch = "detached";
    }

    try {
        commit = git(repoRoot, ["rev-parse", "HEAD"]);
    } catch {
        commit = "";
    }

    try {
        upstream = git(repoRoot, [
            "rev-parse",
            "--abbrev-ref",
            "--symbolic-full-name",
            "@{u}",
        ]);
    } catch {
        upstream = branch !== "detached" ? "origin/" + branch : null;
    }

    if (
        query.refresh === "1" &&
        upstream &&
        canManageTruckNavHost(event)
    ) {
        const slash = upstream.indexOf("/");
        const remote = slash > 0 ? upstream.slice(0, slash) : "origin";
        const remoteBranch =
            slash > 0 ? upstream.slice(slash + 1) : branch;

        try {
            execFileSync("git", ["fetch", remote, remoteBranch], {
                cwd: repoRoot,
                stdio: ["ignore", "pipe", "pipe"],
            });
        } catch (error: any) {
            fetchError =
                error?.stderr?.toString()?.trim() ||
                error?.message ||
                "git fetch failed";
        }
    }

    if (upstream) {
        try {
            const counts = git(repoRoot, [
                "rev-list",
                "--left-right",
                "--count",
                "HEAD..." + upstream,
            ])
                .split(/\s+/)
                .map(Number);
            ahead = counts[0] || 0;
            behind = counts[1] || 0;
        } catch {
            ahead = 0;
            behind = 0;
        }
    }

    const dirtyResult = spawnSync(
        "git",
        [
            "diff",
            "--quiet",
            "--",
            ".",
            ":(exclude)public/data/ats/**",
            ":(exclude)public/sprites/ats/**",
            ":(exclude)public/data/ets2/**",
            ":(exclude)public/sprites/ets2/**",
        ],
        {
            cwd: repoRoot,
            stdio: "ignore",
        },
    );
    const dirty = dirtyResult.status !== 0;

    let changedFiles: string[] = [];
    if (dirty) {
        try {
            changedFiles = git(repoRoot, [
                "diff",
                "--name-only",
                "--",
                ".",
                ":(exclude)public/data/ats/**",
                ":(exclude)public/sprites/ats/**",
                ":(exclude)public/data/ets2/**",
                ":(exclude)public/sprites/ets2/**",
            ])
                .split(/\r?\n/)
                .filter(Boolean)
                .slice(0, 20);
        } catch {
            changedFiles = [];
        }
    }

    const manifestPath = join(
        repoRoot,
        "public",
        "data",
        "ats",
        "map-data",
        "trucknav-linux-map.json",
    );

    let map: Record<string, any> = { available: false };
    if (existsSync(manifestPath)) {
        try {
            map = {
                available: true,
                ...JSON.parse(readFileSync(manifestPath, "utf8")),
            };
        } catch {
            map = {
                available: false,
                error: "Map manifest could not be read",
            };
        }
    } else {
        const versionPath = join(
            repoRoot,
            "build",
            "map-data",
            "ats-parser",
            "usa-version.txt",
        );
        const graphManifestPath = join(
            repoRoot,
            "public",
            "data",
            "ats",
            "roadnetwork",
            "trucknav-graph-manifest.json",
        );
        const visualManifestPath = join(
            repoRoot,
            "public",
            "data",
            "ats",
            "map-data",
            "trucknav-visual-manifest.json",
        );

        if (
            existsSync(versionPath) &&
            existsSync(graphManifestPath) &&
            existsSync(visualManifestPath)
        ) {
            try {
                const graphManifest = JSON.parse(
                    readFileSync(graphManifestPath, "utf8"),
                );
                const visualManifest = JSON.parse(
                    readFileSync(visualManifestPath, "utf8"),
                );
                map = {
                    available: true,
                    game: "ats",
                    gameVersion: readFileSync(versionPath, "utf8").trim(),
                    projection:
                        graphManifest?.source?.projection ||
                        visualManifest?.projection,
                    supportedDlcs: 18,
                    newestDlc: "South Dakota",
                    southDakotaEdges:
                        graphManifest?.dlcEncoding?.southDakotaEdges,
                    visualFeatures: visualManifest?.features,
                    bounds: visualManifest?.bounds,
                    generatedAt: null,
                };
            } catch {
                map = {
                    available: false,
                    error: "Generated ATS map metadata could not be read",
                };
            }
        }
    }

    const atsSteam = readSteamInstallState("270880");
    const installedSteamBuildId = atsSteam.installedSteamBuildId;
    const installedSteamLastUpdated = atsSteam.installedSteamLastUpdated;

    const mapSteamBuildId =
        typeof map.steamBuildId === "string" ? map.steamBuildId : null;
    const mapUpdateAvailable =
        !!installedSteamBuildId &&
        !!mapSteamBuildId &&
        installedSteamBuildId !== mapSteamBuildId;

    const ets2ManifestPath = join(
        repoRoot,
        "public",
        "data",
        "ets2",
        "map-data",
        "trucknav-linux-map.json",
    );
    let ets2Map: Record<string, any> = { available: false };
    if (existsSync(ets2ManifestPath)) {
        try {
            ets2Map = {
                available: true,
                ...JSON.parse(readFileSync(ets2ManifestPath, "utf8")),
            };
        } catch {
            ets2Map = {
                available: false,
                error: "ETS2 map manifest could not be read",
            };
        }
    }

    const ets2Steam = readSteamInstallState("227300");
    const ets2MapSteamBuildId =
        typeof ets2Map.steamBuildId === "string"
            ? ets2Map.steamBuildId
            : null;
    const ets2MapUpdateAvailable =
        !!ets2Steam.installedSteamBuildId &&
        !!ets2MapSteamBuildId &&
        ets2Steam.installedSteamBuildId !== ets2MapSteamBuildId;

    return {
        access: {
            maintenanceAllowed: canManageTruckNavHost(event),
            clientIp: getTruckNavClientIp(event),
        },
        app: {
            version: displayVersion,
            channel: branch === "master" ? "Stable" : "Testing",
            branch,
            commit,
            shortCommit: commit.slice(0, 10),
            upstream,
            dirty,
            changedFiles,
            ahead,
            behind,
            updateAvailable: behind > 0 && ahead === 0,
            fetchError,
        },
        ats: {
            installedSteamBuildId,
            installedSteamLastUpdated,
        },
        ets2: {
            installedSteamBuildId: ets2Steam.installedSteamBuildId,
            installedSteamLastUpdated: ets2Steam.installedSteamLastUpdated,
            bundledMapAvailable: existsSync(
                join(
                    repoRoot,
                    "public",
                    "data",
                    "ets2",
                    "TRUCKNAV_BUNDLED_MAP.txt",
                ),
            ),
            map: {
                ...ets2Map,
                mapUpdateAvailable: ets2MapUpdateAvailable,
            },
        },
        map: {
            ...map,
            mapUpdateAvailable,
        },
    };
});
