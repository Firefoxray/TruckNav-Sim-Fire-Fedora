<script lang="ts" setup>
import type { MapLayerVisibility } from "~/composables/Settings";

const { activeSettings, updateProfile } = useSettings();

const layerRows: Array<{
    key: keyof MapLayerVisibility;
    label: string;
    icon: string;
    detail: string;
}> = [
    {
        key: "poiIcons",
        label: "Services & POIs",
        icon: "lucide:map-pin",
        detail: "Fuel, repair, dealers, rest areas and other map POIs",
    },
    {
        key: "roadIcons",
        label: "Road icons",
        icon: "lucide:signpost",
        detail: "Road-side and road-specific map symbols",
    },
    {
        key: "cityLabels",
        label: "City labels",
        icon: "lucide:building-2",
        detail: "Cities, capitals and smaller place names",
    },
    {
        key: "regionLabels",
        label: "Region labels",
        icon: "lucide:map",
        detail: "State/country labels and borders",
    },
    {
        key: "facilityAreas",
        label: "Facility areas",
        icon: "lucide:warehouse",
        detail: "Depots, service areas and mapped facility shapes",
    },
];

function toggleLayer(key: keyof MapLayerVisibility) {
    updateProfile("mapLayers", {
        ...activeSettings.value.mapLayers,
        [key]: !activeSettings.value.mapLayers[key],
    });
}
</script>

<template>
    <div class="map-legend">
        <div class="legend-title">
            <div>
                <strong>Map legend</strong>
                <span>Visibility</span>
            </div>
            <Icon name="lucide:layers-3" size="22" />
        </div>

        <div class="legend-reference">
            <div class="reference-row">
                <span
                    class="legend-dot truck-dot"
                    :style="{ background: activeSettings.themeColor }"
                ></span>
                <span>Your truck</span>
            </div>
            <div class="reference-row">
                <span
                    class="legend-line"
                    :style="{ background: activeSettings.routeColor }"
                ></span>
                <span>TruckNav route</span>
            </div>
            <div class="reference-row">
                <span class="legend-block"></span>
                <span>Mapped facility / lot</span>
            </div>
        </div>

        <div class="legend-divider"></div>

        <button
            v-for="row in layerRows"
            :key="row.key"
            class="legend-toggle"
            :class="{ disabled: !activeSettings.mapLayers[row.key] }"
            @click.prevent="toggleLayer(row.key)"
            :title="row.detail"
        >
            <Icon :name="row.icon" size="20" />
            <div class="legend-toggle-text">
                <strong>{{ row.label }}</strong>
                <span>{{ row.detail }}</span>
            </div>
            <Icon
                :name="
                    activeSettings.mapLayers[row.key]
                        ? 'lucide:eye'
                        : 'lucide:eye-off'
                "
                size="19"
            />
        </button>
    </div>
</template>

<style
    scoped
    lang="scss"
    src="~/assets/scss/scoped/map/mapLegend.scss"
></style>
