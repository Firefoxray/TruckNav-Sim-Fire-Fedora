<script lang="ts" setup>
interface LinuxStatus {
    access?: {
        maintenanceAllowed?: boolean;
        clientIp?: string;
    };
    app: {
        version?: string;
        channel?: string;
        branch: string;
        commit: string;
        shortCommit: string;
        upstream: string | null;
        dirty: boolean;
        changedFiles?: string[];
        ahead: number;
        behind: number;
        updateAvailable: boolean;
        fetchError?: string | null;
    };
    ats?: {
        installedSteamBuildId?: string | null;
        installedSteamLastUpdated?: string | null;
    };
    ets2?: {
        installedSteamBuildId?: string | null;
        installedSteamLastUpdated?: string | null;
        bundledMapAvailable?: boolean;
        map?: {
            available: boolean;
            game?: string;
            gameVersion?: string;
            generatedAt?: string;
            projection?: string;
            supportedDlcs?: number;
            newestDlc?: string;
            visualFeatures?: number;
            steamBuildId?: string | null;
            mapUpdateAvailable?: boolean;
        };
    };
    map: {
        available: boolean;
        game?: string;
        gameVersion?: string;
        generatedAt?: string;
        projection?: string;
        supportedDlcs?: number;
        newestDlc?: string;
        southDakotaEdges?: number;
        visualFeatures?: number;
        steamBuildId?: string | null;
        mapUpdateAvailable?: boolean;
    };
}

interface LinuxJob {
    action: "update-app" | "rebuild-map";
    game?: "ats" | "ets2" | null;
    running: boolean;
    exitCode: number | null;
    startedAt?: string;
    logTail: string[];
}

const { settings } = useSettings();
const selectedGame = computed(() => settings.value.selectedGame || "ats");

const status = ref<LinuxStatus | null>(null);
const loading = ref(false);
const actionLoading = ref<"update-app" | "rebuild-map" | null>(null);
const job = ref<LinuxJob | null>(null);
let pollTimer: ReturnType<typeof setInterval> | null = null;

const maintenanceAllowed = computed(
    () => status.value?.access?.maintenanceAllowed === true,
);

const appStateText = computed(() => {
    if (!status.value) return "Checking...";
    if (status.value.app.dirty) return "Local changes";
    if (status.value.app.behind > 0) {
        return (
            String(status.value.app.behind) +
            " update" +
            (status.value.app.behind === 1 ? "" : "s") +
            " available"
        );
    }
    if (status.value.app.ahead > 0) {
        return (
            String(status.value.app.ahead) +
            " local commit" +
            (status.value.app.ahead === 1 ? "" : "s") +
            " ahead"
        );
    }
    return "Up to date";
});

const appStateClass = computed(() => {
    if (!status.value) return "neutral";
    if (status.value.app.dirty) return "warning";
    if (status.value.app.updateAvailable) return "update";
    return "ok";
});

const mapVersionText = computed(() => {
    if (selectedGame.value === "ets2") {
        const ets2Map = status.value?.ets2?.map;
        if (ets2Map?.available) {
            return ets2Map.gameVersion
                ? "ETS2 " + ets2Map.gameVersion
                : "ETS2 map ready";
        }
        return status.value?.ets2?.bundledMapAvailable
            ? "ETS2 bundled map"
            : "ETS2 map not built";
    }

    if (!status.value?.map.available) return "Not built";
    return status.value.map.gameVersion
        ? "ATS " + status.value.map.gameVersion
        : "ATS map ready";
});

const mapStateText = computed(() => {
    if (selectedGame.value === "ets2") {
        const ets2Map = status.value?.ets2?.map;
        if (ets2Map?.available) {
            if (ets2Map.mapUpdateAvailable) return "Update available";
            if (!ets2Map.steamBuildId) return "Tracking not initialized";
            return "Current";
        }
        return status.value?.ets2?.bundledMapAvailable
            ? "Bundled"
            : "Missing";
    }

    if (!status.value?.map.available) return "Missing";
    if (status.value.map.mapUpdateAvailable) return "Update available";
    if (!status.value.map.steamBuildId) return "Tracking not initialized";
    return "Current";
});

const mapStateClass = computed(() => {
    if (selectedGame.value === "ets2") {
        const ets2Map = status.value?.ets2?.map;
        if (ets2Map?.mapUpdateAvailable) return "update";
        if (ets2Map?.available && ets2Map.steamBuildId) return "ok";
        return status.value?.ets2?.bundledMapAvailable
            ? "ok"
            : "warning";
    }

    if (!status.value?.map.available) return "warning";
    if (status.value.map.mapUpdateAvailable) return "update";
    if (!status.value.map.steamBuildId) return "warning";
    return "ok";
});

const changedFilesText = computed(() => {
    const files = status.value?.app.changedFiles || [];
    if (!files.length) return "";
    if (files.length <= 3) return files.join(", ");
    return files.slice(0, 3).join(", ") + " +" + String(files.length - 3);
});

async function refreshStatus(fetchRemote = false) {
    loading.value = true;
    try {
        status.value = await $fetch<LinuxStatus>("/api/linux/status", {
            query: fetchRemote ? { refresh: "1" } : undefined,
        });
    } catch (error) {
        console.error("Failed to load TruckNav Linux status:", error);
    } finally {
        loading.value = false;
    }
}

async function refreshJob() {
    try {
        const result = await $fetch<LinuxJob | null>("/api/linux/job");
        job.value = result;

        if (result && !result.running) {
            actionLoading.value = null;
            if (pollTimer) {
                clearInterval(pollTimer);
                pollTimer = null;
            }
            await refreshStatus(true);
        }
    } catch (error) {
        console.error("Failed to check TruckNav Linux job:", error);
    }
}

async function startAction(action: "update-app" | "rebuild-map") {
    if (
        action === "rebuild-map" &&
        !window.confirm(
            "Rebuild the " +
                selectedGame.value.toUpperCase() +
                " map from your installed game files? This can take a while.",
        )
    ) {
        return;
    }

    actionLoading.value = action;
    try {
        await $fetch("/api/linux/action", {
            method: "POST",
            body: {
                action,
                game: selectedGame.value,
            },
        });
        await refreshJob();
        if (!pollTimer) {
            pollTimer = setInterval(refreshJob, 1500);
        }
    } catch (error: any) {
        console.error("Failed to start TruckNav Linux action:", error);
        actionLoading.value = null;
        alert(
            error?.data?.statusMessage ||
                error?.message ||
                "Could not start the requested action.",
        );
    }
}

onMounted(async () => {
    await refreshStatus(false);
    await refreshJob();
    if (job.value?.running && !pollTimer) {
        actionLoading.value = job.value.action;
        pollTimer = setInterval(refreshJob, 1500);
    }
});

onUnmounted(() => {
    if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
    <section class="linux-control-center">
        <div class="linux-heading">
            <div>
                <div class="eyebrow">TruckNav Linux</div>
                <h2>Local control center</h2>
            </div>
            <div class="linux-heading-right">
                <span
                    v-if="status?.app.version"
                    class="version-channel"
                >
                    {{ status.app.version }}
                    {{ status.app.channel || "" }}
                </span>
                <div class="linux-icon">
                    <Icon
                        :name="
                            maintenanceAllowed
                                ? 'lucide:square-terminal'
                                : 'lucide:laptop'
                        "
                        size="24"
                    />
                </div>
            </div>
        </div>

        <div
            v-if="status && !maintenanceAllowed"
            class="remote-view-note"
        >
            <Icon name="lucide:shield-alert" size="16" />
            <span>
                View-only connection. Shared administration is disabled on
                the TruckNav host.
            </span>
        </div>
        <div
            v-else-if="status && maintenanceAllowed"
            class="remote-view-note lan-enabled"
        >
            <Icon name="lucide:wifi" size="16" />
            <span>
                Shared management enabled
                <template v-if="status.access?.clientIp">
                    · {{ status.access.clientIp }}
                </template>
            </span>
        </div>

        <div class="linux-status-grid">
            <article class="status-card">
                <div class="status-card-heading">
                    <Icon name="lucide:git-branch" size="18" />
                    <span>App</span>
                    <span class="status-pill" :class="appStateClass">
                        {{ appStateText }}
                    </span>
                </div>

                <template v-if="status">
                    <strong>{{ status.app.branch }}</strong>
                    <span class="status-detail">
                        {{ status.app.shortCommit }}
                        <template v-if="status.app.dirty"> · modified</template>
                    </span>
                    <span
                        v-if="status.app.dirty && changedFilesText"
                        class="status-detail changed-files"
                        :title="status.app.changedFiles?.join('\n')"
                    >
                        {{ changedFilesText }}
                    </span>
                </template>
                <span v-else class="status-detail">Reading repository…</span>
            </article>

            <article class="status-card">
                <div class="status-card-heading">
                    <Icon name="lucide:map" size="18" />
                    <span>Map data</span>
                    <span class="status-pill" :class="mapStateClass">
                        {{ mapStateText }}
                    </span>
                </div>

                <strong>{{ mapVersionText }}</strong>
                <span class="status-detail">
                    <template v-if="selectedGame === 'ets2'">
                        <template v-if="status?.ets2?.map?.available">
                            {{
                                status.ets2.map.newestDlc ||
                                "Fresh locally generated Europe map"
                            }}
                            <template v-if="status.ets2.map.supportedDlcs">
                                · {{ status.ets2.map.supportedDlcs }} DLCs
                            </template>
                        </template>
                        <template v-else-if="status?.ets2?.bundledMapAvailable">
                            Legacy TruckNav ETS2 bundle · rebuild for current
                            Europe data
                        </template>
                        <template v-else>
                            Rebuild from the installed ETS2 game files.
                        </template>
                    </template>
                    <template v-else-if="status?.map.available">
                        {{
                            status.map.newestDlc ||
                            "Current locally generated map"
                        }}
                        <template v-if="status.map.supportedDlcs">
                            · {{ status.map.supportedDlcs }} DLCs
                        </template>
                    </template>
                    <template v-else>
                        Rebuild from the installed ATS game files.
                    </template>
                </span>
                <span
                    v-if="
                        selectedGame === 'ats' &&
                        status?.ats?.installedSteamBuildId
                    "
                    class="status-detail"
                >
                    ATS build {{ status.ats.installedSteamBuildId }}
                    <template v-if="status.map.steamBuildId">
                        · map build {{ status.map.steamBuildId }}
                    </template>
                </span>
                <span
                    v-if="
                        selectedGame === 'ets2' &&
                        status?.ets2?.installedSteamBuildId
                    "
                    class="status-detail"
                >
                    ETS2 build {{ status.ets2.installedSteamBuildId }}
                    <template v-if="status.ets2.map?.steamBuildId">
                        · map build {{ status.ets2.map.steamBuildId }}
                    </template>
                </span>
            </article>
        </div>

        <div class="linux-actions">
            <button
                class="linux-action"
                :disabled="loading || !!actionLoading || !maintenanceAllowed"
                @click="refreshStatus(true)"
            >
                <Icon
                    :name="
                        loading
                            ? 'svg-spinners:ring-resize'
                            : 'lucide:refresh-cw'
                    "
                    size="18"
                />
                Check for Updates
            </button>

            <button
                class="linux-action primary"
                :disabled="
                    !maintenanceAllowed ||
                    !!actionLoading ||
                    !status?.app.updateAvailable ||
                    status?.app.dirty
                "
                @click="startAction('update-app')"
            >
                <Icon
                    :name="
                        actionLoading === 'update-app'
                            ? 'svg-spinners:ring-resize'
                            : 'lucide:download'
                    "
                    size="18"
                />
                Update TruckNav
            </button>

            <button
                class="linux-action"
                :disabled="
                    !!actionLoading ||
                    !maintenanceAllowed
                "
                @click="startAction('rebuild-map')"
            >
                <Icon
                    :name="
                        actionLoading === 'rebuild-map'
                            ? 'svg-spinners:ring-resize'
                            : 'lucide:database-zap'
                    "
                    size="18"
                />
                {{
                    selectedGame === "ets2"
                        ? status?.ets2?.map?.mapUpdateAvailable
                            ? "Update ETS2 Map"
                            : "Rebuild ETS2 Map"
                        : status?.map.mapUpdateAvailable
                          ? "Update ATS Map"
                          : "Rebuild ATS Map"
                }}
            </button>
        </div>

        <div v-if="job" class="linux-job" :class="{ running: job.running }">
            <div class="job-heading">
                <Icon
                    :name="
                        job.running
                            ? 'svg-spinners:ring-resize'
                            : job.exitCode === 0
                              ? 'lucide:circle-check'
                              : 'lucide:circle-alert'
                    "
                    size="18"
                />
                <span>
                    {{
                        job.action === "update-app"
                            ? "TruckNav update"
                            : (job.game || selectedGame).toUpperCase() +
                              " map rebuild"
                    }}
                    {{
                        job.running
                            ? "is running…"
                            : job.exitCode === 0
                              ? "finished"
                              : "failed"
                    }}
                </span>
            </div>

            <pre v-if="job.logTail.length">{{ job.logTail.join("\n") }}</pre>

            <p v-if="!job.running && job.exitCode === 0" class="restart-note">
                Reload TruckNav after this finishes. The game can stay open.
            </p>
        </div>
    </section>
</template>

<style scoped lang="scss" src="~/assets/scss/scoped/linuxControlCenter.scss"></style>
