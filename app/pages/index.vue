<script lang="ts" setup>
import { SafeArea, SystemBarsType } from "@capacitor-community/safe-area";
import { isMapDownloaded } from "~/assets/utils/shared/fileManager";

const { isElectron, isMobile } = usePlatform();
const { settings, initSettings } = useSettings();

const currentView = ref<string>("");

onMounted(async () => {
    await initSettings();

    setTimeout(updateSystemBars, 500);
    window.addEventListener("resize", updateSystemBars);

    if (isElectron.value) {
        currentView.value = "desktopHome";
        return;
    }

    if (
        settings.value.startOnMap &&
        settings.value.selectedGame &&
        (await isMapDownloaded(settings.value.selectedGame))
    ) {
        currentView.value = "map";
    } else {
        currentView.value = "gameManager";
    }
});

onUnmounted(() => {
    window.removeEventListener("resize", updateSystemBars);
});

watch(currentView, async () => {
    await nextTick();
    updateSystemBars();

    if (isElectron.value && currentView.value === "desktopHome") {
        (window as any).electronAPI.setWindowSize(950, 700, false, false);
    }
});

const updateSystemBars = async () => {
    if (!isMobile.value) return;

    try {
        const isLandscape = window.innerWidth > window.innerHeight;

        if (isLandscape) {
            await SafeArea.hideSystemBars({ type: SystemBarsType.StatusBar });
            await SafeArea.hideSystemBars({
                type: SystemBarsType.NavigationBar,
            });
        } else {
            await SafeArea.showSystemBars({ type: SystemBarsType.StatusBar });
            await SafeArea.hideSystemBars({
                type: SystemBarsType.NavigationBar,
            });
        }
    } catch (e) {
        console.error("Bars update failed", e);
    }
};

const launchGameManager = () => (currentView.value = "gameManager");
const launchMap = () => (currentView.value = "map");
const goToDesktopIndex = () => (currentView.value = "desktopHome");

const goHome = () => {
    if (isElectron.value) currentView.value = "desktopHome";
    else currentView.value = "gameManager";
};
</script>

<template>
    <template v-if="isElectron">
        <Transition name="page-fade">
            <DesktopIndex
                v-show="currentView === 'desktopHome'"
                @connected="launchGameManager"
            />
        </Transition>
    </template>

    <Transition name="page-fade">
        <GameManager
            v-show="currentView === 'gameManager'"
            @go-back="goToDesktopIndex"
            @connected="launchMap"
        />
    </Transition>

    <Transition name="page-fade">
        <LazyMap
            v-if="currentView === 'map'"
            :goHome="goHome"
            :key="settings.selectedGame ?? 'none'"
        />
    </Transition>
</template>
