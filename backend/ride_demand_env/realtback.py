from fastapi import FastAPI, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import pymysql
import pandas as pd
import geopandas as gpd
import geopy.distance
import re

app = FastAPI()

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection details
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "Aadithya@1124",
    "database": "nammayattri",
}

def get_db_connection():
    """Establish a MySQL database connection."""
    try:
        conn = pymysql.connect(**DB_CONFIG)
        return conn
    except pymysql.MySQLError as e:
        print(f"❌ Database Connection Error: {e}")
        raise HTTPException(status_code=500, detail="Database connection failed!")

# Load Bangalore ward boundary data
try:
    ward_map = gpd.read_file("BBMP.geojson")
    ward_map["Latitude"] = ward_map.geometry.centroid.y
    ward_map["Longitude"] = ward_map.geometry.centroid.x
    ward_map["KGISWardNo"] = ward_map["KGISWardNo"].astype(str)  # Ensure it's string for merging
    print("✅ Bangalore ward boundary data loaded!")
except FileNotFoundError:
    print("❌ Error: BBMP.geojson not found.")
    raise RuntimeError("BBMP.geojson file is missing!")

def get_real_time_demand():
    """Fetch ride demand data from the past 5 minutes."""
    conn = get_db_connection()
    query = """
        SELECT ward_num, SUM(bookings) AS total_bookings
        FROM ward_demand
        WHERE created_at >= NOW() - INTERVAL 5 MINUTE
        GROUP BY ward_num
        ORDER BY total_bookings DESC;
    """
    demand_data = pd.read_sql(query, conn)
    conn.close()

    if demand_data.empty:
        print("⚠️ No real-time demand data available!")
        return demand_data

    # ✅ Convert "b_105" -> "105" for merging
    demand_data["ward_num"] = demand_data["ward_num"].apply(lambda x: re.sub(r"^b_", "", x)).astype(str)

    print("✅ Real-time demand data loaded!")
    return demand_data

def find_nearest_high_demand_ward(lat: float, lon: float):
    """Finds the nearest ward with high ride demand using real-time data."""
    demand_data = get_real_time_demand()

    if demand_data.empty:
        raise HTTPException(status_code=500, detail="No real-time demand data available!")

    # ✅ Merge demand data with BBMP.geojson using fixed formats
    merged_data = demand_data.merge(
        ward_map[["KGISWardNo", "Latitude", "Longitude"]],
        left_on="ward_num", right_on="KGISWardNo",
        how="left"
    )

    # Debugging
    print("🔹 Merged Data Sample:")
    print(merged_data.head())

    merged_data = merged_data.dropna(subset=["Latitude", "Longitude"])

    min_distance = float('inf')
    nearest_ward = None

    for _, row in merged_data.iterrows():
        ward_coords = (row["Latitude"], row["Longitude"])
        user_coords = (lat, lon)
        distance = geopy.distance.geodesic(user_coords, ward_coords).km

        if distance < min_distance:
            min_distance = distance
            nearest_ward = row

    if nearest_ward is None:
        raise HTTPException(status_code=404, detail="No nearby high-demand ward found!")

    return {
        "ward": nearest_ward["ward_num"],
        "latitude": nearest_ward["Latitude"],
        "longitude": nearest_ward["Longitude"],
        "bookings": int(nearest_ward["total_bookings"]),
        "distance_km": round(min_distance, 2)
    }

@app.get("/nearest-ward")
def get_nearest_ward(lat: float = Query(...), lon: float = Query(...)):
    """API endpoint to get the nearest high-demand ward based on real-time data."""
    return find_nearest_high_demand_ward(lat, lon)
