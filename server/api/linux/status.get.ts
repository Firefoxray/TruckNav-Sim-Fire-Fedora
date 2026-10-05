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

    let installedSteamBuildId: string | null = null;
    let installedSteamLastUpdated: string | null = null;

    const steamManifestCandidates = [
        join(
            process.env.HOME || "",
            ".local",
            "share",
            "Steam",
            "steamapps",
            "appmanifest_270880.acf",
        ),
        join(
            process.env.HOME || "",
            ".steam",
            "steam",
            "steamapps",
            "appmanifest_270880.acf",
        ),
    ];

    for (const steamManifestPath of steamManifestCandidates) {
        if (!existsSync(steamManifestPath)) continue;

        try {
            const text = readFileSync(steamManifestPath, "utf8");
            const buildMatch = text.match(/"buildid"\s+"([^"]+)"/);
            const updatedMatch = text.match(/"LastUpdated"\s+"([^"]+)"/);
            installedSteamBuildId = buildMatch?.[1] || null;
            installedSteamLastUpdated = updatedMatch?.[1] || null;
            break;
        } catch {
            // Try the next common Steam location.
        }
    }

    const mapSteamBuildId =
        typeof map.steamBuildId === "string" ? map.steamBuildId : null;
    const mapUpdateAvailable =
        !!installedSteamBuildId &&
        !!mapSteamBuildId &&
        installedSteamBuildId !== mapSteamBuildId;

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
            bundledMapAvailable: existsSync(
                join(
                    repoRoot,
                    "public",
                    "data",
                    "ets2",
                    "TRUCKNAV_BUNDLED_MAP.txt",
                ),
            ),
        },
        map: {
            ...map,
            mapUpdateAvailable,
        },
    };
});
