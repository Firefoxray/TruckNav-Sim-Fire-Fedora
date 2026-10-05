<script lang="ts" setup>
const props = defineProps<{
    routeDistanceConverted: number;
    distanceUnit: string;
    routeEta: string;
    nextStopDistanceConverted?: number | null;
    nextStopEta?: string;
}>();
</script>

<template>
    <div>
        <Icon name="lucide:flag-triangle-right" size="22" />
        <div class="right">
            <div
                v-if="nextStopDistanceConverted != null"
                class="next-stop-line"
            >
                <span class="trip-label">Next</span>
                <span>
                    {{ nextStopDistanceConverted }} {{ distanceUnit }},
                    {{ nextStopEta }}
                </span>
            </div>
            <div class="total-line">
                <span
                    v-if="nextStopDistanceConverted != null"
                    class="trip-label"
                >
                    Total
                </span>
                <span>{{ routeDistanceConverted }} {{ distanceUnit }}, </span>
                <span>{{ routeEta }}</span>
            </div>
        </div>
        <button class="nav-btn icon-btn">
            <Icon name="lucide:chevron-up" />
        </button>
    </div>
</template>

<style
    lang="scss"
    scoped
    src="~/assets/scss/scoped/navigation/compactTrip.scss"
></style>
