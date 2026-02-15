import mapboxgl from "mapbox-gl";
import {APIConfig} from "./service_config.js"

const mapTrace = {
    async initMap() {
        mapboxgl.accessToken = APIConfig.mapbox_api_key

        const mapConfig = {
            container: "map",
            style: "mapbox://styles/ehogberg/clyzb3zij01es01qo5mgi3loq",
            //projection: "mercator",
            center: [-20,40],
            zoom: 2
        }

        const map = new mapboxgl.Map(mapConfig)
        const weather_data = await await_weather_data()

        for (const location of weather_data.weather_stations) {
            const marker = new mapboxgl.Marker()
                .setLngLat(location)
                .addTo(map)

            marker.getElement().addEventListener("click", () => {
                new mapboxgl.Popup()
                    .setLngLat(location)
                    .setHTML(`<p>${location[1].toFixed(2)}°, ${location[0].toFixed(2)}°</p>`)
                    .addTo(map)
            })
        }

        map.resize()

        window.addEventListener("phx:location_added", (event) => {
            const new_location = event.detail
            const lngLat = [new_location.lon, new_location.lat]

            const marker = new mapboxgl.Marker()
                .setLngLat(lngLat)
                .addTo(map)

            marker.getElement().addEventListener("click", () => {
                new mapboxgl.Popup()
                    .setLngLat(lngLat)
                    .setHTML(`<p>${new_location.lat.toFixed(2)}°, ${new_location.lon.toFixed(2)}°</p>`)
                    .addTo(map)
            })
        })
    },

    mounted() {
        this.initMap()
        this.pushEventTo(this.el, "after_map_render", {})
    }
};

function await_weather_data() {
    return new Promise((resolve) => {
        window.addEventListener("phx:initiate_weather_data", (event) => {
            resolve(event.detail)
        });
    });
}

export {mapTrace};