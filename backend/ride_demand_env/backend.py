from fastapi import FastAPI, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import pandas as pd
import geopandas as gpd
import geopy.distance

app = FastAPI()

# Allow frontend requests from any origin (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load ride demand data (processed data with ward bookings)
try:
    demand_data = pd.read_csv("processed_ride_data.csv")
    print("✅ Ride demand data loaded successfully!")
except FileNotFoundError:
    print("❌ Error: processed_ride_data.csv not found.")
    raise RuntimeError("processed_ride_data.csv file is missing!")

# Load Bangalore ward boundary data
try:
    ward_map = gpd.read_file("BBMP.geojson")
    print("✅ Bangalore ward boundary data loaded!")
except FileNotFoundError:
    print("❌ Error: BBMP.geojson not found.")
    raise RuntimeError("BBMP.geojson file is missing!")

# Extract centroid coordinates (latitude & longitude)
ward_map["Latitude"] = ward_map.geometry.centroid.y
ward_map["Longitude"] = ward_map.geometry.centroid.x

# Merge demand data with ward coordinates
demand_data = demand_data.merge(ward_map[["KGISWardName", "Latitude", "Longitude"]], 
                                left_on="Ward", right_on="KGISWardName", how="left")

# Fill missing coordinates with NaN
if demand_data["Latitude"].isnull().any() or demand_data["Longitude"].isnull().any():
    print("⚠️ Warning: Some wards are missing coordinates!")

def find_nearest_high_demand_ward(lat: float, lon: float):
    """Finds the nearest ward with high ride demand."""
    
    if demand_data.empty:
        raise HTTPException(status_code=500, detail="No demand data available!")

    # Sort by highest bookings
    high_demand_wards = demand_data.sort_values(by="Bookings", ascending=False).dropna(subset=["Latitude", "Longitude"])
    
    min_distance = float('inf')
    nearest_ward = None

    for _, row in high_demand_wards.iterrows():
        ward_coords = (row["Latitude"], row["Longitude"])
        user_coords = (lat, lon)
        distance = geopy.distance.geodesic(user_coords, ward_coords).km

        if distance < min_distance:
            min_distance = distance
            nearest_ward = row

    if nearest_ward is None:
        raise HTTPException(status_code=404, detail="No nearby high-demand ward found!")

    return {
        "ward": nearest_ward["Ward"],
        "latitude": nearest_ward["Latitude"],
        "longitude": nearest_ward["Longitude"],
        "bookings": int(nearest_ward["Bookings"]),
        "distance_km": round(min_distance, 2)
    }

@app.get("/nearest-ward")
def get_nearest_ward(lat: float = Query(...), lon: float = Query(...)):
    """API endpoint to get nearest high-demand ward based on location."""
    return find_nearest_high_demand_ward(lat, lon)
