const geoLocation = {
    mounted() {
        if (!navigator.geolocation) return;

        navigator.geolocation.getCurrentPosition(
            (position) => {
                this.pushEvent("add_geolocation", {
                    lat: position.coords.latitude,
                    lon: position.coords.longitude
                });
            },
            (error) => {
                console.debug("Geolocation unavailable:", error.message);
            }
        );
    }
};

export {geoLocation}
