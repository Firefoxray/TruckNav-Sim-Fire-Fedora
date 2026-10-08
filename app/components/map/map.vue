<script lang="ts" setup>
import { ref, onMounted, shallowRef, Transition } from "vue";
import "maplibre-gl/dist/maplibre-gl.css";
import maplibregl from "maplibre-gl";
import { usePlatform } from "~/composables/Platform";
import {
    blendWithBg,
    darkenColor,
    lightenColor,
} from "~/assets/utils/shared/colors";
import { generateTruckIcon } from "~/assets/utils/map/markers";
import type {
    MapLayerVisibility,
    MapStyle,
} from "~/composables/Settings";

defineProps<{ goHome: () => void }>();

// MAP STATE
const mapEl = shallowRef<HTMLElement | null>(null);
const map = shallowRef<maplibregl.Map | null>(null);
const isSettingsPanelOpened = ref(false);
const isLegendOpened = ref(false);
const isClickingEnabled = ref(true);

// UI STATE
const isSheetHidden = ref(false);

// JOB STATE
const currentJobKey = ref<string>("");

// NOTIFICATION TRIGGERS
const clickingNotificationTrigger = ref(0);

// Telemetry Data
const {
    startTelemetry,
    stopTelemetry,
    gameTime,
    gameConnected,
    truckCoords,
    truckSpeed,
    speedLimit,
    truckHeading,
    fuel,
    restStoptime,
    restStopMinutes,
    hasInGameMarker,
    hasActiveJob,
    destinationCity,
    scale,
    averageSpeed,
    destinationCompany,
} = useEtsTelemetry();

// Map Areas Data
const { loadLocationData, findDestinationCoords } = useCityData();

// Check Platform
const { isElectron, isMobile, isWeb } = usePlatform();

// Graph manipulation
const { loading, progress, adjacency, nodeCoords, initializeGraphData } =
    useGraphSystem();

// Maplibre Camera
const {
    isCameraLocked,
    isAutoFollowEnabled,
    isHeadingUp,
    mapBearing,
    isNavigating,
    initCameraListeners,
    followTruck,
    startNavigationMode,
    stopNavigationMode,
    initMarker,
    updateMarkerSize,
    updateMarkerImage,
    toggleAutoFollow,
    toggleHeadingUp,
    setNorthUp,
} = useMapCamera(map);

const {
    setupRouteLayer,
    handleMultiRouteCalculation,
    handleRouteClick,
    updateRouteProgress,
    clearRouteState,
    destinationName,
    routeDistance,
    routeEta,
    nextStopDistance,
    nextStopEta,
    isCalculating: isCalculatingRoute,
    isWorkerReady,
    initWorkerData,
    destroyWorker,
    isRouteActive,
    routeFound,
    fullRouteDirections,
    nextTurnDistance,
    waypointList,
    removeWaypointAtIndex,
} = useRouteController(map, adjacency, nodeCoords, stopNavigationMode);

// Settings Controller
const { activeSettings, settings } = useSettings();
const { t } = useTranslations();

let uiTimer: ReturnType<typeof setTimeout> | null = null;
let routeTimer: ReturnType<typeof setTimeout> | null = null;

loading.value = true;
progress.value = 0;

const isTruckSpawned = computed(() => {
    return (
        truckCoords.value &&
        (truckCoords.value[0] !== 0 || truckCoords.value[1] !== 0)
    );
});

// We check if it has active job, if it has one, plot a route
watch(
    [
        hasActiveJob,
        destinationCity,
        destinationCompany,
        gameConnected,
        loading,
        isWorkerReady,
        isTruckSpawned,
    ],
    async ([
        hasJob,
        city,
        company,
        isConnected,
        isLoading,
        isWorkerReady,
        truckReady,
    ]) => {
        if (!truckCoords.value) return;
        if (isLoading || !isWorkerReady || !isConnected || !truckReady) {
            currentJobKey.value = "";
            return;
        }

        const newJobKey = hasJob ? `${city}|${company}` : "";

        if (hasJob && newJobKey === currentJobKey.value) return;

        if (routeTimer) clearTimeout(routeTimer);

        if (hasJob && newJobKey !== currentJobKey.value) {
            const destCoords = findDestinationCoords(city, company);

            if (destCoords) {
                currentJobKey.value = newJobKey;
                clearRouteState();
                isClickingEnabled.value = false;

                await handleRouteClick(
                    destCoords,
                    truckCoords.value,
                    truckHeading.value,
                    scale.value,
                    false,
                    averageSpeed.value,
                );
            }
        } else if (!hasJob && currentJobKey.value !== "") {
            clearRouteState();
            stopNavigationMode();
            currentJobKey.value = "";
        }
    },
);

watch(
    [hasActiveJob, gameConnected, loading, isWorkerReady, isTruckSpawned],
    ([hasJob, isGameConnected, isLoading, isWorkerReady, truckReady]) => {
        if (!truckCoords.value) return;
        if (
            isLoading ||
            !isWorkerReady ||
            !isGameConnected ||
            hasJob ||
            !truckReady
        )
            return;

        const destination = activeSettings.value.lastDestination;

        if (destination && !isRouteActive.value && !isCalculatingRoute.value) {
            handleRouteClick(
                destination,
                truckCoords.value,
                truckHeading.value,
                scale.value,
                true,
                averageSpeed.value,
            );
        }
    },
);

watch(
    () => activeSettings.value.themeColor,
    async (newColor) => {
        if (!map.value) return;

        const newTruckImg = await generateTruckIcon(newColor);
        updateMarkerImage(newTruckImg.src);

        applyMapStyle();
    },
);

watch(
    [
        () => activeSettings.value.backgroundColor,
        () => activeSettings.value.landColor,
        () => activeSettings.value.roadColor,
        () => activeSettings.value.mapStyle,
    ],
    () => applyMapStyle(),
);

watch(
    () => settings.value.truckMarkerSize,
    (newSize) => {
        if (newSize) {
            updateMarkerSize(newSize);
        }
    },
);

const MAP_LAYER_GROUPS: Record<keyof MapLayerVisibility, string[]> = {
    poiIcons: ["all-sprites"],
    roadIcons: ["road-sprites"],
    cityLabels: ["city-labels", "capital-major-labels", "village-labels"],
    regionLabels: ["country-labels", "state-borders"],
    facilityAreas: ["prefab-zones", "maparea-zones"],
};


function applyMapStyle() {
    if (!map.value) return;

    const style = activeSettings.value.mapStyle as MapStyle;
    const themeColor = activeSettings.value.themeColor;
    const usesGeneratedAtsGeometry =
        settings.value.selectedGame === "ats" &&
        (!activeSettings.value.activeMod ||
            activeSettings.value.activeMod === "none");

    const truckNavMapAreas: any = [
        "match",
        ["get", "color"],
        0,
        "#3d546e",
        1,
        "#4a5f7a",
        2,
        "#556b7f",
        3,
        "#6b7f93",
        4,
        "#7d93a7",
        "#3d546e",
    ];

    const terrainMapAreas: any = [
        "match",
        ["get", "color"],
        0,
        "#59694b",
        1,
        "#687658",
        2,
        "#7b7658",
        3,
        "#8a8063",
        4,
        "#6e755f",
        "#59694b",
    ];

    const minimalMapAreas: any = [
        "match",
        ["get", "color"],
        0,
        "#354250",
        1,
        "#3c4956",
        2,
        "#43505d",
        3,
        "#495663",
        4,
        "#505d6a",
        "#354250",
    ];

    const prefabTruckNav: any = [
        "match",
        ["get", "color"],
        0,
        blendWithBg(lightenColor(themeColor, 0.3), 0.6),
        1,
        blendWithBg(lightenColor(themeColor, 0.3), 0.6),
        2,
        blendWithBg(lightenColor(themeColor, 0), 0.6),
        3,
        blendWithBg(lightenColor(themeColor, 0.3), 0.6),
        "#3d546e",
    ];

    const prefabTerrain: any = [
        "match",
        ["get", "color"],
        0,
        "#81785f",
        1,
        "#81785f",
        2,
        "#94876b",
        3,
        "#756f59",
        "#81785f",
    ];

    const palette =
        style === "terrain"
            ? {
                  // The generated ATS vector map contains roads, areas and
                  // prefabs, but not a continuous land-cover polygon. Its
                  // legacy water basemap can cover the entire game extent.
                  // Paint the missing terrain as land and keep that legacy
                  // water layer subtle instead of letting it tint everything
                  // ocean blue. No real elevation data is implied here.
                  background: "#718563",
                  water: "#315f79",
                  waterOpacity: usesGeneratedAtsGeometry ? 0.14 : 1,
                  country: "#677b55",
                  countryOpacity: usesGeneratedAtsGeometry ? 0.28 : 0.72,
                  waterOutline: "#7d9dab",
                  waterOutlineOpacity: usesGeneratedAtsGeometry ? 0.18 : 0.7,
                  road: "#d0c39a",
                  roadOpacity: 0.96,
                  baseLine: "#718066",
                  mapAreas: terrainMapAreas,
                  mapAreaOpacity: 0.5,
                  prefabs: prefabTerrain,
                  prefabOpacity: 0.72,
                  stateBorder: "#9aa489",
                  stateOpacity: 0.5,
                  label: "#f3eedf",
                  labelHalo: "#263126",
              }
            : style === "minimal"
              ? {
                    background: darkenColor(
                        activeSettings.value.backgroundColor,
                        0.12,
                    ),
                    water: darkenColor(activeSettings.value.landColor, 0.08),
                    waterOpacity: 1,
                    waterOutlineOpacity: 0.7,
                    country: darkenColor(activeSettings.value.landColor, 0.28),
                    countryOpacity: 0.32,
                    waterOutline: darkenColor(
                        activeSettings.value.landColor,
                        0.32,
                    ),
                    road: activeSettings.value.roadColor,
                    roadOpacity: 0.55,
                    baseLine: darkenColor(activeSettings.value.roadColor, 0.2),
                    mapAreas: minimalMapAreas,
                    mapAreaOpacity: 0.16,
                    prefabs: prefabTruckNav,
                    prefabOpacity: 0.22,
                    stateBorder: darkenColor(
                        activeSettings.value.roadColor,
                        0.1,
                    ),
                    stateOpacity: 0.22,
                    label: "#d9dee5",
                    labelHalo: "#1c242d",
                }
              : {
                    background: activeSettings.value.backgroundColor,
                    water: activeSettings.value.landColor,
                    waterOpacity: 1,
                    waterOutlineOpacity: 0.7,
                    country: darkenColor(activeSettings.value.landColor, 0.4),
                    countryOpacity: 0.4,
                    waterOutline: darkenColor(
                        activeSettings.value.landColor,
                        0.15,
                    ),
                    road: activeSettings.value.roadColor,
                    roadOpacity: 1,
                    baseLine: "#3d546e",
                    mapAreas: truckNavMapAreas,
                    mapAreaOpacity: 0.5,
                    prefabs: prefabTruckNav,
                    prefabOpacity: 1,
                    stateBorder: "#3d546e",
                    stateOpacity: 0.4,
                    label: "#ffffff",
                    labelHalo: "#ffffff",
                };

    const setPaint = (layer: string, property: string, value: any) => {
        if (!map.value?.getLayer(layer)) return;
        map.value.setPaintProperty(layer, property as any, value);
    };

    // Real relief is optional; it becomes visible only after the terrain
    // PMTiles have been generated from parsed ATS elevation samples.
    if (map.value.getLayer("terrain-elevation")) {
        map.value.setLayoutProperty(
            "terrain-elevation",
            "visibility",
            style === "terrain" ? "visible" : "none",
        );
    }

    setPaint("background", "background-color", palette.background);
    setPaint("water", "fill-color", palette.water);
    setPaint("water", "fill-opacity", palette.waterOpacity);
    setPaint("country-borders", "fill-color", palette.country);
    setPaint("country-borders", "fill-opacity", palette.countryOpacity);
    setPaint("water-outline", "line-color", palette.waterOutline);
    setPaint("water-outline", "line-opacity", palette.waterOutlineOpacity);
    setPaint("lines", "line-color", palette.baseLine);
    setPaint("roads", "line-color", palette.road);
    setPaint("roads", "line-opacity", palette.roadOpacity);
    setPaint("maparea-zones", "fill-color", palette.mapAreas);
    setPaint("maparea-zones", "fill-opacity", palette.mapAreaOpacity);
    setPaint("prefab-zones", "fill-color", palette.prefabs);
    setPaint("prefab-zones", "fill-opacity", palette.prefabOpacity);
    setPaint("state-borders", "line-color", palette.stateBorder);
    setPaint("state-borders", "line-opacity", palette.stateOpacity);

    for (const layer of [
        "village-labels",
        "city-labels",
        "capital-major-labels",
        "country-labels",
    ]) {
        setPaint(layer, "text-color", palette.label);
        setPaint(layer, "text-halo-color", palette.labelHalo);
    }
}

function applyMapLayerVisibility() {
    if (!map.value) return;

    for (const [group, layerIds] of Object.entries(MAP_LAYER_GROUPS)) {
        const visible =
            activeSettings.value.mapLayers[
                group as keyof MapLayerVisibility
            ];

        for (const layerId of layerIds) {
            if (!map.value.getLayer(layerId)) continue;
            map.value.setLayoutProperty(
                layerId,
                "visibility",
                visible ? "visible" : "none",
            );
        }
    }
}

watch(
    () => activeSettings.value.mapLayers,
    () => applyMapLayerVisibility(),
    { deep: true },
);

watch(
    () => activeSettings.value.fontFamily,
    (newFont) => {
        if (!map.value) return;

        const textLayers = [
            "village-labels",
            "city-labels",
            "capital-major-labels",
            "country-labels",
        ];

        textLayers.forEach((layerId) => {
            if (map.value!.getLayer(layerId)) {
                map.value!.setLayoutProperty(layerId, "text-font", [newFont]);
            }
        });
    },
);

watch(routeFound, (newVal) => {
    if (newVal !== null) {
        if (uiTimer) clearTimeout(uiTimer);

        uiTimer = setTimeout(() => {
            routeFound.value = null;
        }, 1000);
    }
});

// Initial truck positioning may lock the camera once. Reconnecting must not
// steal manual panning/zooming unless auto-follow was explicitly enabled.
let hasInitializedCameraFollow = false;
watch([loading, gameConnected], ([isLoading, isGameConnected]) => {
    if (isLoading || !isGameConnected) return;
    if (!hasInitializedCameraFollow) {
        hasInitializedCameraFollow = true;
        isCameraLocked.value = true;
    } else if (isAutoFollowEnabled.value) {
        isCameraLocked.value = true;
    }
});

watch(gameConnected, (isConnected) => {
    if (!map.value) return;
    if (!isConnected) {
        isCameraLocked.value = false;
        clearRouteState();
    }
});

onMounted(async () => {
    await loadLocationData();
    if (!mapEl.value) return;
    if (isElectron.value) {
        (window as any).electronAPI.setWindowSize(950, 700, true, true);
    }

    try {
        const mapInstance = await initializeMap(mapEl.value);
        map.value = markRaw(mapInstance);
        if (!map.value) return;

        const initialTruckImg = await generateTruckIcon(
            activeSettings.value.themeColor,
        );
        map.value.on("load", async () => {
            initMarker(initialTruckImg.src, settings.value.truckMarkerSize);
            const graphData = await initializeGraphData();
            if (!graphData) return;

            const { nodes, graphBuffer, geometryBuffer } = graphData;
            if (!nodes || !graphBuffer || !geometryBuffer) return;

            initWorkerData(nodes, graphBuffer, geometryBuffer);

            setupRouteLayer();
            initCameraListeners();
            applyMapStyle();
            applyMapLayerVisibility();
        });

        map.value.on("click", async (e) => {
            const features = map.value!.queryRenderedFeatures(e.point, {
                layers: ["destination-layer"],
            });
            if (features.length > 0) return;

            if (!isClickingEnabled.value) return;
            if (!gameConnected.value) return;
            if (!truckCoords.value) return;

            const currentScale =
                scale.value > 0
                    ? scale.value
                    : settings.value.selectedGame === "ats"
                    ? 20
                    : 19;

            waypointList.value.push([e.lngLat.lng, e.lngLat.lat]);

            await handleMultiRouteCalculation(
                truckCoords.value,
                truckHeading.value,
                currentScale,
                averageSpeed.value,
            );
        });

        startTelemetry(() => {
            onTelemetryUpdate();
        });
    } catch (e) {
        console.error(e);
    }
});

onUnmounted(() => {
    stopTelemetry();
    destroyWorker();

    if (routeTimer) clearTimeout(routeTimer);
    if (uiTimer) clearTimeout(uiTimer);

    if (map.value) {
        map.value.remove();
        map.value = null;
    }
});

function onTelemetryUpdate() {
    if (!truckCoords.value || !map.value) return;

    followTruck(truckCoords.value, truckHeading.value);

    if (isRouteActive.value) {
        updateRouteProgress(
            truckCoords.value,
            truckHeading.value,
            scale.value,
            averageSpeed.value,
        );
    }
}

function onStartNavigation() {
    if (!truckCoords.value) return;

    startNavigationMode(truckCoords.value, truckHeading.value);

    isSheetHidden.value = true;
}

function onSheetClosed() {
    isSheetHidden.value = false;
}

function toggleEnableClicking() {
    isClickingEnabled.value = !isClickingEnabled.value;

    clickingNotificationTrigger.value++;
}

const onResetNorth = () => {
    setNorthUp();
};

const onToggleFullscreen = async () => {
    const target = document.documentElement;

    try {
        if (!document.fullscreenElement) {
            await target.requestFullscreen();
        } else {
            if (document.exitFullscreen) {
                await document.exitFullscreen();
            }
        }

        setTimeout(() => {
            map.value?.resize();
        }, 100);
    } catch (err) {
        console.error("Fullscreen error:", err);
    }
};

const toggleSettingsPanel = () => {
    isSettingsPanelOpened.value = !isSettingsPanelOpened.value;
    if (isSettingsPanelOpened.value) isLegendOpened.value = false;
};

const toggleLegend = () => {
    isLegendOpened.value = !isLegendOpened.value;
};

const onCancelRoute = () => {
    clearRouteState();
    stopNavigationMode();
};
</script>

<template>
    <div
        ref="wrapperEl"
        class="full-page-wrapper"
        :class="{ 'platform-mobile': isMobile }"
    >
        <div ref="mapEl" class="map-container"></div>

        <div class="ui-safe-container">
            <Transition name="ui-layer-fade">
                <div v-show="!isSettingsPanelOpened" class="map-ui-layer">
                    <Transition name="fade">
                        <LoadingScreen v-if="loading" :progress="progress" />
                    </Transition>

                    <TopBar
                        v-show="settings.activeUiComponents.includes('topBar')"
                        :fuel="fuel"
                        :game-connected="gameConnected"
                        :game-time="gameTime"
                        :rest-stop-minutes="restStopMinutes"
                        :rest-stop-time="restStoptime"
                        :truck-speed="truckSpeed"
                        :is-web="isWeb"
                    />

                    <div class="left-buttons">
                        <HudButton :onClick="goHome">
                            <Icon name="lucide:arrow-left" class="icon" />
                        </HudButton>

                        <HudButton :onClick="toggleSettingsPanel">
                            <Icon name="lucide:settings" class="icon" />
                        </HudButton>

                        <HudButton
                            :is-active="isLegendOpened"
                            :class="{ 'green-icon': isLegendOpened }"
                            :onClick="toggleLegend"
                            title="Map legend and layer visibility"
                        >
                            <Icon name="lucide:layers-3" class="icon" />
                        </HudButton>
                    </div>

                    <Transition name="panel-pop">
                        <div v-if="isLegendOpened" class="map-legend-wrapper">
                            <MapLegend />
                        </div>
                    </Transition>

                    <ManeuverCard
                        v-show="
                            isNavigating && activeSettings.hasTurnNavigation
                        "
                        :upcoming-turns="fullRouteDirections"
                        :distance-to-next-turn="nextTurnDistance"
                        :next-instruction="
                            fullRouteDirections[1]?.text || t('map.followRoute')
                        "
                    />

                    <NotificationGeneral
                        :trigger="clickingNotificationTrigger"
                        :text="
                            isClickingEnabled
                                ? t('map.tappingEnabled')
                                : t('map.tappingDisabled')
                        "
                    >
                        <template #icon>
                            <Icon
                                v-if="isClickingEnabled"
                                class="notification-icon"
                                name="lucide:pointer"
                                size="24"
                                :style="{ color: '#4caf50' }"
                            />

                            <Icon
                                v-else
                                class="notification-icon"
                                name="lucide:pointer-off"
                                size="24"
                                :style="{ color: '#dd4a34' }"
                            />
                        </template>
                    </NotificationGeneral>

                    <NotificationRoute
                        :is-route-found="routeFound"
                        :is-calculating-route="isCalculatingRoute"
                    />

                    <div class="hud-buttons">
                        <HudButton v-if="isWeb" :onClick="onToggleFullscreen">
                            <Icon name="lucide:fullscreen" class="icon" />
                        </HudButton>

                        <HudButton
                            :onClick="onResetNorth"
                            aria-label="Reset map north"
                            title="Reset map north"
                        >
                            <Icon
                                name="lucide:compass"
                                class="icon compass-icon"
                                :style="{
                                    transform:
                                        'rotate(' + -mapBearing + 'deg)',
                                }"
                            />
                        </HudButton>

                        <HudButton
                            :is-active="isHeadingUp"
                            :class="{ 'green-icon': isHeadingUp }"
                            :onClick="toggleHeadingUp"
                            aria-label="Toggle heading-up map"
                            :title="
                                isHeadingUp
                                    ? 'Heading up — click for north up'
                                    : 'North/manual up — click for heading up'
                            "
                        >
                            <Icon
                                name="lucide:navigation"
                                class="icon heading-icon"
                            />
                        </HudButton>

                        <HudButton
                            :is-active="isAutoFollowEnabled"
                            :class="{ 'green-icon': isAutoFollowEnabled }"
                            :onClick="toggleAutoFollow"
                        >
                            <Icon
                                v-if="isAutoFollowEnabled"
                                name="lucide:locate-fixed"
                                class="icon"
                            />
                            <Icon v-else name="lucide:locate" class="icon" />
                        </HudButton>

                        <HudButton
                            :is-active="isClickingEnabled"
                            :class="
                                isClickingEnabled ? 'green-icon' : 'red-icon'
                            "
                            :onClick="toggleEnableClicking"
                        >
                            <Icon
                                v-if="isClickingEnabled"
                                name="lucide:pointer"
                                class="icon"
                            />
                            <Icon
                                v-else
                                name="lucide:pointer-off"
                                class="icon"
                            />
                        </HudButton>
                    </div>

                    <SpeedLimit
                        v-show="
                            speedLimit > 0 &&
                            settings.activeUiComponents.includes('speedLimit')
                        "
                        :truck-speed="truckSpeed"
                        :speed-limit="speedLimit"
                    />

                    <div class="warnings">
                        <WarningSlide
                            :show-if="hasInGameMarker && !isRouteActive"
                            :reset-on="isRouteActive"
                            :text="t('map.externalRouteDetected')"
                        />

                        <WarningSlide
                            :show-if="!gameConnected"
                            :reset-on="gameConnected"
                            :text="t('common.gameOffline')"
                        />
                    </div>

                    <Transition name="sheet-slide" @after-leave="onSheetClosed">
                        <SheetSlide
                            v-if="isRouteActive"
                            :on-stop-navigation="onCancelRoute"
                            :is-navigating="isNavigating"
                            :on-start-navigation="onStartNavigation"
                            :destination-name="destinationName"
                            v-model:is-sheet-hidden="isSheetHidden"
                            :route-distance="routeDistance"
                            :route-eta="routeEta"
                            :next-stop-distance="nextStopDistance"
                            :next-stop-eta="nextStopEta"
                            :speed-limit="speedLimit"
                            :truck-speed="truckSpeed"
                        />
                    </Transition>
                </div>
            </Transition>

            <Transition name="panel-pop">
                <SettingsPanel
                    v-show="isSettingsPanelOpened"
                    :close-panel="toggleSettingsPanel"
                />
            </Transition>
        </div>
    </div>
</template>

<style scoped lang="scss" src="~/assets/scss/scoped/map/map.scss"></style>
