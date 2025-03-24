from fastapi import FastAPI, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
import pandas as pd
import geopandas as gpd
import geopy.distance
import osmnx as ox
import networkx as nx
from shapely.geometry import Point, LineString
from datetime import datetime, timedelta

app = FastAPI()

# Enable CORS for frontend integration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Supabase Configuration
SUPABASE_URL = "https://vsrafcmvrzprgxsvjwba.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzcmFmY212cnpwcmd4c3Zqd2JhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE4NzQ3MzUsImV4cCI6MjA1NzQ1MDczNX0.wTXpoTTvUDT7DIhatQIxiHihtdD5l9IuxG-a-82R8xw"
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Load Bangalore ward boundary data with proper CRS conversion
try:
    ward_map = gpd.read_file("BBMP.geojson").to_crs(epsg=4326)  # Convert to projected CRS
    ward_map["Latitude"] = ward_map.geometry.centroid.y
    ward_map["Longitude"] = ward_map.geometry.centroid.x
    print("✅ Bangalore ward boundary data loaded successfully!")
except FileNotFoundError:
    print("❌ Error: BBMP.geojson not found.")
    raise RuntimeError("BBMP.geojson file is missing!")


def get_real_time_demand():
    """Fetches all ride demand data from Supabase without time filtering."""
    try:
        response = (
            supabase.table("ward_demand")
            .select("ward_num, bookings, created_at")  # Fetch all records
            .execute()
        )

        #print(f"🔍 Raw Supabase Response: {response}")  # Debugging Step

        if not response.data or len(response.data) == 0:
            print("❌ No demand data found in Supabase!")
            raise HTTPException(status_code=500, detail="No real-time demand data available!")

        # Convert to DataFrame
        demand_data = pd.DataFrame(response.data)

        # Aggregate bookings per ward
        demand_data = demand_data.groupby("ward_num")["bookings"].sum().reset_index()
        demand_data.rename(columns={"bookings": "total_bookings"}, inplace=True)

        #print(f"✅ Demand data processed: {demand_data}")
        return demand_data

    except Exception as e:
        print(f"❌ Error fetching real-time demand: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch real-time demand.")



def get_major_roads(ward_boundary, ward_name):
    """Fetches major roads within the given ward boundary using OpenStreetMap."""
    try:
        print(f"🛣 Fetching major roads for {ward_name}...")
        graph = ox.graph_from_place(ward_name, network_type="drive")
        edges = ox.graph_to_gdfs(graph, nodes=False)
        major_roads = edges[edges["highway"].isin(["primary", "secondary", "tertiary"])]

        if major_roads.empty:
            return {"message": f"No major roads found in {ward_name}."}

        road_coords = [
            list(row.geometry.coords) for _, row in major_roads.iterrows() if isinstance(row.geometry, LineString)
        ]
        print(f"✅ Successfully fetched roads for {ward_name}.")
        return {"roads": road_coords}
    except Exception as e:
        print(f"⚠️ Warning: Could not fetch roads for {ward_name}: {e}")
        return {"message": "Failed to fetch road data."}


def find_roaming_area(lat: float, lon: float):
    """Finds the best ward for drivers to roam based on real-time demand."""
    try:
        print("🔍 Fetching real-time demand data...")
        demand_data = get_real_time_demand()
        print(f"✅ Demand Data:\n{demand_data}")

        # Ensure ward numbers are treated as strings
        demand_data["ward_num"] = demand_data["ward_num"].astype(str).str.replace(r"^b_", "", regex=True)
        ward_map["KGISWardNo"] = ward_map["KGISWardNo"].astype(str)

        print("🔍 Merging demand data with ward boundaries...")
        print(f"👉 Ward Map Data:\n{ward_map[['KGISWardNo', 'KGISWardName', 'Latitude', 'Longitude']].head()}")

        merged_data = demand_data.merge(
            ward_map[["KGISWardNo", "KGISWardName", "Latitude", "Longitude", "geometry"]],
            left_on="ward_num", right_on="KGISWardNo",
            how="left"
        )
        print(f"✅ Merged Data:\n{merged_data}")

        if merged_data.empty:
            print("❌ No matching ward data found!")
            raise HTTPException(status_code=500, detail="No real-time demand data available!")

        min_distance = float("inf")
        best_ward = None

        for _, row in merged_data.iterrows():
            if pd.isna(row["Latitude"]) or pd.isna(row["Longitude"]):
                print(f"⚠️ Skipping ward {row['KGISWardNo']} due to missing coordinates!")
                continue

            distance = geopy.distance.geodesic((lat, lon), (row["Latitude"], row["Longitude"])).km
            print(f"📍 Ward {row['KGISWardNo']} → Distance: {distance} km")

            if distance < min_distance:
                min_distance = distance
                best_ward = row

        if best_ward is None:
            print("❌ No nearby high-demand ward found!")
            raise HTTPException(status_code=404, detail="No nearby high-demand ward found!")

        road_network = get_major_roads(best_ward["geometry"], best_ward["KGISWardName"])

        return {
            "ward": best_ward["KGISWardNo"],
            "ward_name": best_ward["KGISWardName"],
            "latitude": best_ward["Latitude"],
            "longitude": best_ward["Longitude"],
            "bookings": int(best_ward["total_bookings"]),
            "distance_km": round(min_distance, 2),
            "road_network": road_network if road_network else "Road data unavailable"
        }

    except Exception as e:
        print(f"❌ Error in find_roaming_area: {e}")
        raise HTTPException(status_code=500, detail=f"Server error: {str(e)}")



@app.get("/roaming-area")
def get_roaming_area(lat: float = Query(...), lon: float = Query(...)):
    """API endpoint to suggest a roaming area for drivers."""
    return find_roaming_area(lat, lon)
