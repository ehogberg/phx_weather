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
            new mapboxgl.Marker()
                .setLngLat(location)
                .addTo(map)
                .getElement()
                .addEventListener("click", (event) => {
                    console.debug(event)
                })
        }

        map.resize()

        window.addEventListener("phx:location_added", (event) => {
            console.debug("new location received")

            new_location = event.detail

            new mapboxgl.Marker()
                .setLngLat([new_location.lon, new_location.lat])
                .addTo(map)
                .getElement()
                .addEventListener("click", (event) => {
                    console.debug("clicked")
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