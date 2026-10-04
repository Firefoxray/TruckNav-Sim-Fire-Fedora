<script lang="ts" setup>
interface LinuxStatus {
    app: {
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
    running: boolean;
    exitCode: number | null;
    startedAt?: string;
    logTail: string[];
}

const status = ref<LinuxStatus | null>(null);
const loading = ref(false);
const actionLoading = ref<"update-app" | "rebuild-map" | null>(null);
const job = ref<LinuxJob | null>(null);
let pollTimer: ReturnType<typeof setInterval> | null = null;

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
    if (!status.value?.map.available) return "Not built";
    return status.value.map.gameVersion
        ? "ATS " + status.value.map.gameVersion
        : "ATS map ready";
});

const mapStateText = computed(() => {
    if (!status.value?.map.available) return "Missing";
    if (status.value.map.mapUpdateAvailable) return "Update available";
    if (!status.value.map.steamBuildId) return "Tracking not initialized";
    return "Current";
});

const mapStateClass = computed(() => {
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
    actionLoading.value = action;
    try {
        await $fetch("/api/linux/action", {
            method: "POST",
            body: { action },
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
            <div class="linux-icon">
                <Icon name="lucide:square-terminal" size="24" />
            </div>
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
                    <template v-if="status?.map.available">
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
                    v-if="status?.ats?.installedSteamBuildId"
                    class="status-detail"
                >
                    ATS build {{ status.ats.installedSteamBuildId }}
                    <template v-if="status.map.steamBuildId">
                        · map build {{ status.map.steamBuildId }}
                    </template>
                </span>
            </article>
        </div>

        <div class="linux-actions">
            <button
                class="linux-action"
                :disabled="loading || !!actionLoading"
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
                :disabled="!!actionLoading"
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
                    status?.map.mapUpdateAvailable
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
                            : "ATS map rebuild"
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
                Reload TruckNav after this finishes. ATS can stay open.
            </p>
        </div>
    </section>
</template>

<style scoped lang="scss" src="~/assets/scss/scoped/linuxControlCenter.scss"></style>
