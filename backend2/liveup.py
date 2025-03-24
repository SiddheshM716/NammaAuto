import time
import threading
import requests
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

app = FastAPI()

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Supabase client
url: str = "https://vsrafcmvrzprgxsvjwba.supabase.co"
key: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzcmFmY212cnpwcmd4c3Zqd2JhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE4NzQ3MzUsImV4cCI6MjA1NzQ1MDczNX0.wTXpoTTvUDT7DIhatQIxiHihtdD5l9IuxG-a-82R8xw"
supabase: Client = create_client(url, key)

# Google Maps Routes API key
api_key = "AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954"
# In-memory storage for driver waypoints
driver_waypoints = {}

# Function to get a route from Google Maps Routes API
def get_route(origin_lat, origin_lon, dest_lat, dest_lon, api_key):
    url = "https://routes.googleapis.com/directions/v2:computeRoutes"
    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline",
    }
    payload = {
        "origin": {
            "location": {
                "latLng": {
                    "latitude": origin_lat,
                    "longitude": origin_lon,
                }
            }
        },
        "destination": {
            "location": {
                "latLng": {
                    "latitude": dest_lat,
                    "longitude": dest_lon,
                }
            }
        },
        "travelMode": "DRIVE",
    }
    response = requests.post(url, headers=headers, json=payload)
    data = response.json()

    if "routes" in data and len(data["routes"]) > 0:
        # Extract the encoded polyline
        encoded_polyline = data["routes"][0]["polyline"]["encodedPolyline"]
        return encoded_polyline
    else:
        logging.error("Error fetching route: %s", data)
        return None
# Function to update driver location along the route
def update_driver_location():
    while True:
        try:
            # Fetch all drivers from Supabase
            drivers = supabase.table("drivers").select("*").execute().data

            for driver in drivers:
                driver_id = driver["id"]
                lat = driver["latitude"]
                lon = driver["longitude"]
                destination_lat = driver["destination_lat"]
                destination_lon = driver["destination_lon"]

                if not destination_lat or not destination_lon:
                    logging.warning("Driver %d has no destination set", driver_id)
                    continue

                # Fetch the route polyline for the driver (if not already fetched)
                if driver_id not in driver_waypoints:
                    encoded_polyline = get_route(lat, lon, destination_lat, destination_lon, api_key)
                    if not encoded_polyline:
                        logging.error("No route found for driver %d", driver_id)
                        continue
                    # Decode the polyline to get waypoints
                    driver_waypoints[driver_id] = _decode_polyline(encoded_polyline)

                # Get the next waypoint
                waypoints = driver_waypoints[driver_id]
                if not waypoints:
                    logging.warning("Driver %d has no waypoints", driver_id)
                    continue

                # Move to the next waypoint
                next_waypoint = waypoints.pop(0)  # Remove the first waypoint
                new_lat, new_lon = next_waypoint

                # Update the driver's location in Supabase
                supabase.table("drivers").update({
                    "latitude": new_lat,
                    "longitude": new_lon
                }).eq("id", driver_id).execute()

                # Log the update
                logging.info("Updated driver %d: Latitude = %f, Longitude = %f", driver_id, new_lat, new_lon)

        except Exception as e:
            logging.error("Error updating driver locations: %s", str(e))

        time.sleep(1)  # Update every second for real-time simulation

# Function to decode a Google Maps encoded polyline
def _decode_polyline(encoded_polyline):
    index = 0
    lat = 0
    lng = 0
    coordinates = []
    while index < len(encoded_polyline):
        shift = 0
        result = 0
        while True:
            b = ord(encoded_polyline[index]) - 63
            result |= (b & 0x1F) << shift
            shift += 5
            index += 1
            if b < 0x20:
                break
        dlat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += dlat

        shift = 0
        result = 0
        while True:
            b = ord(encoded_polyline[index]) - 63
            result |= (b & 0x1F) << shift
            shift += 5
            index += 1
            if b < 0x20:
                break
        dlng = ~(result >> 1) if (result & 1) else (result >> 1)
        lng += dlng

        coordinates.append((lat / 1e5, lng / 1e5))
    return coordinates

# Start the driver update function in a separate thread
@app.on_event("startup")
async def startup():
    logging.info("Starting driver location update thread.")
    update_thread = threading.Thread(target=update_driver_location)
    update_thread.daemon = True
    update_thread.start()

# API Endpoint to get all driver locations
@app.get("/drivers")
def get_drivers():
    try:
        drivers = supabase.table("drivers").select("*").execute().data
        logging.info("Fetched latest driver locations.")
        return {"drivers": drivers}
    except Exception as e:
        logging.error("Error fetching driver locations: %s", str(e))
        return {"error": str(e)}

# API Endpoint to get the route polyline for a driver
@app.get("/route")
def get_route_polyline(origin_lat: float, origin_lon: float, dest_lat: float, dest_lon: float):
    try:
        encoded_polyline = get_route(origin_lat, origin_lon, dest_lat, dest_lon, api_key)
        if encoded_polyline:
            return {"polyline": encoded_polyline}
        else:
            return {"error": "No route found"}
    except Exception as e:
        logging.error("Error fetching route polyline: %s", str(e))
        return {"error": str(e)}
    
    
@app.get("/route/{driver_id}")
def get_route_polyline(driver_id: int):
    try:
        # Fetch the driver's current location and destination
        driver = supabase.table("drivers").select("*").eq("id", driver_id).execute().data[0]
        origin_lat = driver["latitude"]
        origin_lon = driver["longitude"]
        dest_lat = driver["destination_lat"]
        dest_lon = driver["destination_lon"]

        # Fetch the route polyline
        encoded_polyline = get_route(origin_lat, origin_lon, dest_lat, dest_lon, api_key)
        if encoded_polyline:
            return {"polyline": encoded_polyline}
        else:
            return {"error": "No route found"}
    except Exception as e:
        logging.error("Error fetching route polyline: %s", str(e))
        return {"error": str(e)}