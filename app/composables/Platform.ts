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

    const isLinuxWeb = computed(() => {
        if (!isWeb.value || typeof window === "undefined") return false;
        return (
            /Linux/i.test(navigator.userAgent) &&
            !/Android/i.test(navigator.userAgent)
        );
    });

    const isLocalWebHost = computed(() => {
        if (!isWeb.value || typeof window === "undefined") return false;
        const host = window.location.hostname;
        return (
            host === "127.0.0.1" ||
            host === "localhost" ||
            host === "::1"
        );
    });

    const isLinuxLocalWeb = computed(
        () => isLinuxWeb.value && isLocalWebHost.value,
    );

    return {
        isElectron,
        isMobile,
        isWeb,
        isLinuxWeb,
        isLocalWebHost,
        isLinuxLocalWeb,
    };
};
