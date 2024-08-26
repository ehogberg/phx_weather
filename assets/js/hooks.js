import {mapTrace} from "./maps.js"
import {geoLocation} from "./geolocation.js"

const PhxWeatherHooks = {
    Geolocation: geoLocation,
    MapTrace: mapTrace
};

export {PhxWeatherHooks}