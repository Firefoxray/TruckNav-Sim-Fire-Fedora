import { Capacitor } from "@capacitor/core";

export const usePlatform = () => {
    const isElectron = ref(false);
    const isMobile = ref(false);
    const isWeb = ref(false);

    if (typeof window !== "undefined") {
        const platform = Capacitor.getPlatform();

        if (platform === "web") isWeb.value = true;
        if (platform === "electron") isElectron.value = true;
        if (platform === "android" || platform === "ios") isMobile.value = true;
    }

    const isLinuxLocalWeb = computed(() => {
        if (!isWeb.value || typeof window === "undefined") return false;

        const isLinuxDesktop =
            /Linux/i.test(navigator.userAgent) &&
            !/Android/i.test(navigator.userAgent);
        const host = window.location.hostname;
        const isLocalHost =
            host === "127.0.0.1" || host === "localhost" || host === "::1";

        return isLinuxDesktop && isLocalHost;
    });

    return {
        isElectron,
        isMobile,
        isWeb,
        isLinuxLocalWeb,
    };
};
