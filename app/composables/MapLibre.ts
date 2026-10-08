import type { Map as MapLibreGl, StyleSpecification } from "maplibre-gl";
import {
    blendWithBg,
    darkenColor,
    lightenColor,
} from "~/assets/utils/shared/colors";
import { BlobSource } from "~/assets/utils/shared/BlobSource";
import { getMapFileUrl } from "~/assets/utils/shared/fileManager";
import { getActiveMapFolder } from "~/assets/utils/map/helpers";

export async function initializeMap(
    container: HTMLElement,
): Promise<MapLibreGl> {
    const { settings, activeSettings } = useSettings();

    const isFreshAtsBaseMap =
        settings.value.selectedGame === "ats" &&
        (!activeSettings.value.activeMod ||
            activeSettings.value.activeMod === "none");

    const baseUrl = window.location.origin;

    const maplibregl = (await import("maplibre-gl")).default;
    const { Protocol, PMTiles } = await import("pmtiles");

    const protocol = new Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);

    async function loadPmtiles(fileName: string, key: string): Promise<boolean> {
        const folder = getActiveMapFolder(settings.value);
        const url = await getMapFileUrl(
            folder,
            `map-data/tiles/${fileName}.mp3`,
        );

        try {
            const response = await fetch(url);
            if (!response.ok) throw new Error(`Failed to load ${fileName}`);

            const blob = await response.blob();
            const pmtilesInstance = new PMTiles(new BlobSource(blob, key));
            protocol.add(pmtilesInstance);

            console.log(
                `Successfully loaded ${fileName} into memory (${(
                    blob.size /
                    1024 /
                    1024
                ).toFixed(2)} MB)`,
            );
            return true;
        } catch (error) {
            if (fileName === "terrain") {
                // Elevation is optional until the user builds terrain.mp3
                // from their local ATS elevation samples.
                console.info("Optional ATS elevation relief not installed.");
            } else {
                console.error("Error loading PMTiles blob:", error);
            }
            return false;
        }
    }

    const [, , terrainAvailable] = await Promise.all([
        loadPmtiles("roads", "roads"),
        loadPmtiles("map-data-combined", "all-data"),
        isFreshAtsBaseMap
            ? loadPmtiles("terrain", "terrain")
            : Promise.resolve(false),
    ]);

    let freshAtsBounds:
        | [[number, number], [number, number]]
        | null = null;
    let freshAtsPanBounds:
        | [[number, number], [number, number]]
        | null = null;

    if (isFreshAtsBaseMap) {
        try {
            const folder = getActiveMapFolder(settings.value);
            const manifestUrl = await getMapFileUrl(
                folder,
                "map-data/trucknav-visual-manifest.json",
            );
            const response = await fetch(manifestUrl, { cache: "no-store" });
            if (response.ok) {
                const manifest = await response.json();
                const bounds = manifest?.bounds;
                if (
                    bounds &&
                    [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].every(
                        Number.isFinite,
                    )
                ) {
                    const width = Math.max(0.1, bounds.maxX - bounds.minX);
                    const height = Math.max(0.1, bounds.maxY - bounds.minY);
                    const padX = width * 0.03;
                    const padY = height * 0.05;
                    freshAtsBounds = [
                        [bounds.minX - padX, bounds.minY - padY],
                        [bounds.maxX + padX, bounds.maxY + padY],
                    ];
                    // Keep the initial overview snug, but let users pan past
                    // the mapped roads. Previously maxBounds equaled the
                    // fitted bounds, so zoomed-out dragging felt locked.
                    const roamPadX = width * 0.45;
                    const roamPadY = height * 0.45;
                    freshAtsPanBounds = [
                        [bounds.minX - roamPadX, bounds.minY - roamPadY],
                        [bounds.maxX + roamPadX, bounds.maxY + roamPadY],
                    ];
                    console.log(
                        "Using generated ATS initial bounds:",
                        freshAtsBounds,
                        "pan bounds:",
                        freshAtsPanBounds,
                    );
                }
            }
        } catch (error) {
            console.warn("Could not load ATS visual bounds manifest:", error);
        }
    }

    const style: StyleSpecification = {
        version: 8,

        name: "PMTiles (local)",
        sources: {
            [`${settings.value.selectedGame}`]: {
                type: "vector",
                url: `pmtiles://roads`,
            },
        },

        sprite: `${baseUrl}/sprites/${
            activeSettings.value.activeMod !== "none"
                ? activeSettings.value.activeMod
                : settings.value.selectedGame
        }/sprites`,
        glyphs: `${baseUrl}/glyphs/{fontstack}/{range}.pbf`,

        layers: [
            {
                id: "background",
                type: "background",
                paint: {
                    "background-color":
                        activeSettings.value.backgroundColor ?? "#24467b",
                },
            },
            {
                id: "lines",
                type: "line",
                source: `${settings.value.selectedGame}`,
                "source-layer": `${settings.value.selectedGame}`,
                ...(isFreshAtsBaseMap
                    ? {
                          filter: [
                              "==",
                              ["get", "type"],
                              "road",
                          ] as any,
                      }
                    : {}),
                paint: {
                    "line-color": "#3d546e",
                    "line-width": 2,
                },
            },
        ],
    };

    const isProMods = activeSettings.value.activeMod === "promods-europe";

    const proModsBounds: [number[], number[]] = [
        [-40, -30], // [[west, south]
        [75, 88], // [east, north]]
    ];

    const baseEtsBounds: [number[], number[]] = [
        [-30, -23],
        [23, 25],
    ];

    const gameMap = {
        ets: {
            container,
            style,
            center: [0, 0],
            zoom: 6,
            minZoom: 5,
            maxZoom: 13,
            maxPitch: 60,
            fadeDuration: 0,
            attributionControl: false,
            collectResourceTiming: false,
            maxBounds: isProMods ? proModsBounds : baseEtsBounds,
        },

        ats: {
            container,
            style,
            ...(freshAtsBounds
                ? {
                      bounds: freshAtsBounds,
                      fitBoundsOptions: { padding: 40 },
                      maxBounds: freshAtsPanBounds!,
                  }
                : {
                      center: [0, 0],
                      zoom: 6,
                      maxBounds: [
                          [-30, -23],
                          [23, 25],
                      ],
                  }),
            minZoom: 5,
            maxZoom: 13,
            maxPitch: 60,
            fadeDuration: 0,
            attributionControl: false,
            collectResourceTiming: false,
        },
    };

    const selectedMap =
        settings.value.selectedGame === "ets2" ? gameMap.ets : gameMap.ats;
    const map = new maplibregl.Map(selectedMap as maplibregl.MapOptions);

    map.on("error", (e) => {
        console.error(">>> MAP ERROR EVENT:", e);
        if (e.error) {
            console.error("   Message:", e.error.message);
            console.error("   Stack:", e.error.stack);
        }
        // @ts-ignore
        if (e.sourceId) console.error("  Failing Source:", e.sourceId);
        // @ts-ignore
        if (e.tile) console.error("  Failing Tile:", e.tile);
    });

    //// =================> LATER ATS UPDATE <=================

    map.on("load", async () => {
        map.addSource("all-data", {
            type: "vector",
            url: "pmtiles://all-data",
        });

        if (terrainAvailable) {
            map.addSource("terrain-elevation", {
                type: "vector",
                url: "pmtiles://terrain",
            });
            // Game-derived filled elevation contours. Put relief below
            // game roads, prefabs, POIs and labels, but above the base land
            // background. Levels and palette follow the map toolkit's
            // contour layer; no real-world terrain tiles are mixed in.
            map.addLayer(
                {
                    id: "terrain-elevation",
                    type: "fill",
                    source: "terrain-elevation",
                    "source-layer": "contours",
                    layout: {
                        "fill-sort-key": ["get", "elevation"],
                        visibility:
                            activeSettings.value.mapStyle === "terrain"
                                ? "visible"
                                : "none",
                    },
                    paint: {
                        "fill-color": [
                            "interpolate",
                            ["linear"],
                            ["get", "elevation"],
                            -200, "#709567",
                            0, "#709567",
                            100, "#a1b968",
                            150, "#c8c27f",
                            200, "#c6b27e",
                            250, "#b39e78",
                            300, "#a18d73",
                            400, "#918171",
                            500, "#bdb9a8",
                        ],
                        "fill-opacity": 0.95,
                    },
                },
                "lines",
            );
        }

        // WATER
        map.addLayer({
            id: "water",
            type: "fill",
            source: "all-data",
            "source-layer": "water",
            paint: {
                "fill-color": activeSettings.value?.landColor ?? "#272d39",
            },
        });

        // DISPLAYING COUNTRY DELIMITATIONS
        map.addLayer({
            id: "country-borders",
            type: "fill",
            source: "all-data",
            "source-layer": "countries",
            paint: {
                "fill-color": activeSettings.value?.landColor
                    ? darkenColor(activeSettings.value.landColor, 0.4)
                    : "#3d546e",
                "fill-opacity": 0.4,
            },
        });

        ////
        //// LAYERS FOR DISPLAYING
        //// FROM SOURCES
        ////
        // OUTLINE
        map.addLayer({
            id: "water-outline",
            type: "line",
            source: "all-data",
            "source-layer": "water",
            paint: {
                "line-color": activeSettings.value?.landColor
                    ? darkenColor(activeSettings.value.landColor, 0.15)
                    : "#1e3a5f",
                "line-width": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    5,
                    2.5,
                    10,
                    5,
                ],
                "line-opacity": 0.7,
            },
        });

        // THICK ROADS
        map.addLayer({
            id: "roads",
            type: "line",
            source: `${settings.value.selectedGame}`,
            "source-layer": `${settings.value.selectedGame}`,
            ...(isFreshAtsBaseMap
                ? {
                      filter: [
                          "==",
                          ["get", "type"],
                          "road",
                      ] as any,
                  }
                : {}),
            layout: {
                "line-join": ["step", ["zoom"], "miter", 8, "round"],
                "line-cap": ["step", ["zoom"], "butt", 8, "round"],
            },
            paint: {
                "line-color": activeSettings.value?.roadColor
                    ? activeSettings.value.roadColor
                    : "#4a5f7a",
                "line-width": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    5,
                    0.5,
                    9,
                    2,
                    10,
                    6,
                    11,
                    9,
                ],
                "line-opacity": 1,
            },
        });

        // POLYGONS FOR PARKING ETC
        map.addLayer(
            {
                id: "maparea-zones",
                type: "fill",
                source: isFreshAtsBaseMap
                    ? `${settings.value.selectedGame}`
                    : "all-data",
                "source-layer": isFreshAtsBaseMap
                    ? `${settings.value.selectedGame}`
                    : "mapareas",
                ...(isFreshAtsBaseMap
                    ? {
                          filter: [
                              "==",
                              ["get", "type"],
                              "mapArea",
                          ] as any,
                      }
                    : {}),
                paint: {
                    "fill-color": [
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
                    ],
                    "fill-opacity": 0.5,
                },
            },
            "lines",
        );

        // PREFABS FOR SERVICE AREAS     ETC
        const color0 = blendWithBg(
            lightenColor(activeSettings.value.themeColor, 0.3),
            0.6,
        );
        const color1 = blendWithBg(
            lightenColor(activeSettings.value.themeColor, 0),
            0.6,
        );
        map.addLayer(
            {
                id: "prefab-zones",
                type: "fill",
                source: isFreshAtsBaseMap
                    ? `${settings.value.selectedGame}`
                    : "all-data",
                "source-layer": isFreshAtsBaseMap
                    ? `${settings.value.selectedGame}`
                    : "prefabs",
                ...(isFreshAtsBaseMap
                    ? {
                          filter: [
                              "==",
                              ["get", "type"],
                              "prefab",
                          ] as any,
                      }
                    : {}),
                paint: {
                    "fill-color": [
                        "match",
                        ["get", "color"],
                        0,
                        color0,
                        1,
                        color0,
                        2,
                        color1,
                        3,
                        color0,
                        "#3d546e",
                    ],
                },
                minzoom: 8,
            },
            "roads",
        );

        // DISPLAYING VILLAGE NAMES
        map.addLayer({
            id: "village-labels",
            type: "symbol",
            source: "all-data",
            "source-layer": "ets2villages",
            layout: {
                "text-field": ["get", "name"],
                "text-font": [
                    activeSettings.value.fontFamily || "Commissioner",
                ],
                "text-size": 13,
                "text-anchor": "center",
                "text-offset": [0, 0],
                "text-allow-overlap": true,
                "text-ignore-placement": true,
            },
            paint: {
                "text-color": "#ffffff",
            },
            minzoom: 8.2,
        });

        // DISPLAYING STATE DELIMITATIONS
        map.addLayer(
            {
                id: "state-borders",
                type: "line",
                source: "all-data",
                "source-layer": "states",
                paint: {
                    "line-color": "#3d546e",
                    "line-width": 2,
                    "line-opacity": 0.4,
                },
            },
            "lines",
        );

        // ALL SPRITE SHEETS
        map.addLayer({
            id: "all-sprites",
            type: "symbol",
            source: isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "all-data",
            "source-layer": isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "spritelocations",
            filter: isFreshAtsBaseMap
                ? [
                      "all",
                      ["has", "sprite"],
                      ["!=", ["get", "poiType"], "road"],
                  ]
                : ["!=", ["get", "poiType"], "road"],
            minzoom: 8,
            layout: {
                "icon-image": ["get", "sprite"],
                "icon-size": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    7,
                    1,
                    10,
                    1.5,
                    12,
                    2,
                ],
                "icon-allow-overlap": false,
                "symbol-sort-key": [
                    "match",
                    ["get", "sprite"],
                    "gas_ico",
                    1,
                    "service_ico",
                    2,
                    10,
                ],
                "symbol-placement": "point",
            },
        });

        // ROAD POI TYPE
        map.addLayer({
            id: "road-sprites",
            type: "symbol",
            source: isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "all-data",
            "source-layer": isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "spritelocations",
            filter: isFreshAtsBaseMap
                ? [
                      "all",
                      ["has", "sprite"],
                      ["==", ["get", "poiType"], "road"],
                  ]
                : ["==", ["get", "poiType"], "road"],
            minzoom: 8,
            layout: {
                "icon-image": ["get", "sprite"],
                "icon-size": [
                    "interpolate",
                    ["linear"],
                    ["zoom"],
                    7,
                    0.6,
                    10,
                    0.9,
                ],
                "icon-allow-overlap": true,
                "symbol-placement": "point",
            },
        });

        // DISPLAYING CITY NAMES
        map.addLayer({
            id: "city-labels",
            type: "symbol",
            source: isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "all-data",
            "source-layer": isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "cities",
            filter: isFreshAtsBaseMap
                ? [
                      "all",
                      ["==", ["get", "type"], "city"],
                      ["!=", ["get", "capital"], 2],
                  ]
                : ["!=", ["get", "capital"], 2],
            layout: {
                "text-field": ["get", "name"],
                "text-font": [
                    activeSettings.value.fontFamily || "Commissioner",
                ],
                "text-size": 15,
                "text-anchor": "bottom",
                "text-offset": [0, -0.3],
                "text-allow-overlap": true,
                "text-ignore-placement": true,
            },
            paint: {
                "text-color": "#ffffff",

                "text-halo-color": "#ffffff",
                "text-halo-width": 0.3,
            },
            minzoom: 6,
            maxzoom: 8,
        });

        // DISPLAYING CAPITAL NAMES
        map.addLayer({
            id: "capital-major-labels",
            type: "symbol",
            filter: isFreshAtsBaseMap
                ? [
                      "all",
                      ["==", ["get", "type"], "city"],
                      ["==", ["get", "capital"], 2],
                  ]
                : ["==", ["get", "capital"], 2],
            source: isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "all-data",
            "source-layer": isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "cities",
            layout: {
                "text-field": ["get", "name"],
                "text-size": 18,
                "text-font": [
                    activeSettings.value.fontFamily || "Commissioner",
                ],
                "text-anchor": "bottom",
                "text-offset": [0, -0.3],
                "text-allow-overlap": true,
                "text-ignore-placement": true,
            },
            paint: {
                "text-color": "#ffffff",
                "text-halo-color": "#ffffff",
            },

            minzoom: 6,
            maxzoom: 8,
        });

        // DISPLAYING COUNTRY NAMES
        map.addLayer({
            id: "country-labels",
            type: "symbol",
            source: isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "all-data",
            "source-layer": isFreshAtsBaseMap
                ? `${settings.value.selectedGame}`
                : "countrynames",
            ...(isFreshAtsBaseMap
                ? {
                      filter: [
                          "==",
                          ["get", "type"],
                          "country",
                      ] as any,
                  }
                : {}),
            layout: {
                "text-field": ["get", "name"],
                "text-size": 20,
                "text-font": [
                    activeSettings.value.fontFamily || "Commissioner",
                ],
                "text-anchor": "bottom",
                "text-offset": [0, -0.3],
                "text-allow-overlap": true,
                "text-ignore-placement": true,
            },
            paint: {
                "text-color": "#ffffff",
                "text-halo-color": "#ffffff",
                "text-halo-width": 0.5,
            },
            minzoom: 5,
            maxzoom: 6,
        });
    });

    return map;
}
