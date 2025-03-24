from fastapi import FastAPI, Query, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
import mysql.connector
from mysql.connector import Error
from typing import List, Dict, Optional
from datetime import datetime, timedelta
import geopy.distance
import geopandas as gpd
import pandas as pd
from pydantic import BaseModel

# Models for data validation
class Driver(BaseModel):
    driver_id: int
    current_lat: float
    current_lng: float
    current_ward: str
    idle_minutes: int

class WardDemand(BaseModel):
    ward_num: str
    total_bookings: int
    latitude: float
    longitude: float
    distance_km: Optional[float] = None

class HighDemandLocation(BaseModel):
    ward_num: str
    latitude: float
    longitude: float
    total_bookings: int
    distance_km: float
    recommended_roads: List[str] = []

# FastAPI app setup
app = FastAPI(title="Auto Driver Demand Prediction Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection
def get_db_connection():
    try:
        connection = mysql.connector.connect(
            host="localhost",
            user="yourusername",
            password="yourpassword",
            database="yourdatabase"
        )
        return connection
    except Error as e:
        print(f"Database connection error: {e}")
        raise HTTPException(status_code=500, detail="Database connection failed")

# Load Bangalore ward boundary data
try:
    ward_map = gpd.read_file("BBMP.geojson")
    # Extract centroid coordinates
    ward_map["latitude"] = ward_map.geometry.centroid.y
    ward_map["longitude"] = ward_map.geometry.centroid.x
    # Create ward_num to coordinates mapping
    ward_coordinates = {}
    for _, row in ward_map.iterrows():
        ward_id = row.get("KGISWardNo", "").lower()
        if ward_id:
            ward_id = f"b_{ward_id}" if not ward_id.startswith("b_") else ward_id
            ward_coordinates[ward_id] = {
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "name": row.get("KGISWardName", "")
            }
    print("✅ Bangalore ward boundary data loaded!")
except FileNotFoundError:
    print("❌ Error: BBMP.geojson not found.")
    ward_coordinates = {}
    # We'll continue and use database coordinates if available

# Get high demand wards based on recent data
def get_high_demand_wards(conn, limit: int = 5, hours_lookback: int = 2):
    cursor = conn.cursor(dictionary=True)
    
    # Query for high demand wards based on recent bookings
    query = """
    SELECT ward_num, SUM(bookings) AS total_bookings
    FROM ward_demand
    WHERE date = CURDATE() AND hour >= HOUR(NOW()) - %s
    GROUP BY ward_num
    ORDER BY total_bookings DESC
    LIMIT %s
    """
    
    cursor.execute(query, (hours_lookback, limit))
    results = cursor.fetchall()
    cursor.close()
    
    # Add coordinates to results
    high_demand_wards = []
    for row in results:
        ward = row["ward_num"]
        if ward in ward_coordinates:
            high_demand_wards.append({
                "ward_num": ward,
                "total_bookings": row["total_bookings"],
                "latitude": ward_coordinates[ward]["latitude"],
                "longitude": ward_coordinates[ward]["longitude"]
            })
    
    return high_demand_wards

# Get idle drivers
def get_idle_drivers(conn, idle_threshold_minutes: int = 10):
    cursor = conn.cursor(dictionary=True)
    
    query = """
    SELECT driver_id, current_ward, 
           TIMESTAMPDIFF(MINUTE, last_ride_time, NOW()) AS idle_minutes
    FROM driver_activity
    WHERE TIMESTAMPDIFF(MINUTE, last_ride_time, NOW()) >= %s
    """
    
    cursor.execute(query, (idle_threshold_minutes,))
    results = cursor.fetchall()
    cursor.close()
    
    return results

# Find nearest high demand ward for a specific driver
def find_nearest_high_demand_ward(driver_lat: float, driver_lng: float, high_demand_wards: List[Dict]):
    if not high_demand_wards:
        return None
        
    min_distance = float('inf')
    nearest_ward = None
    
    driver_coords = (driver_lat, driver_lng)
    
    for ward in high_demand_wards:
        ward_coords = (ward["latitude"], ward["longitude"])
        distance = geopy.distance.geodesic(driver_coords, ward_coords).km
        
        # Add distance to ward info
        ward["distance_km"] = round(distance, 2)
        
        if distance < min_distance:
            min_distance = distance
            nearest_ward = ward
    
    return nearest_ward

# Get recommended roads within a ward (placeholder - would need actual road data)
def get_recommended_roads(ward_num: str, conn):
    # This would ideally query a table of road-level demand data
    # For now, returning placeholder data
    return [
        "MG Road",
        "Brigade Road",
        "Residency Road"
    ]

# API Endpoints
@app.get("/idle-drivers", response_model=List[Driver])
def get_all_idle_drivers(idle_minutes: int = Query(10, description="Minimum idle time in minutes"),
                         db_conn = Depends(get_db_connection)):
    """Get all drivers who have been idle for at least the specified time."""
    drivers = get_idle_drivers(db_conn, idle_minutes)
    return drivers

@app.get("/high-demand-wards", response_model=List[WardDemand])
def get_demand_wards(limit: int = Query(5, description="Number of high demand wards to return"),
                     hours: int = Query(2, description="Hours to look back for demand data"),
                     db_conn = Depends(get_db_connection)):
    """Get the highest demand wards based on recent booking data."""
    wards = get_high_demand_wards(db_conn, limit, hours)
    return wards

@app.get("/recommendations/{driver_id}", response_model=HighDemandLocation)
def get_driver_recommendation(driver_id: int, db_conn = Depends(get_db_connection)):
    """Get a personalized recommendation for where an idle driver should go."""
    # Get driver information
    cursor = db_conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM driver_activity WHERE driver_id = %s", (driver_id,))
    driver = cursor.fetchone()
    cursor.close()
    
    if not driver:
        raise HTTPException(status_code=404, detail=f"Driver {driver_id} not found")
    
    # Check if driver is idle
    idle_minutes = (datetime.now() - driver["last_ride_time"]).total_seconds() / 60
    if idle_minutes < 10:
        raise HTTPException(status_code=400, detail=f"Driver {driver_id} is not idle (only {int(idle_minutes)} minutes since last ride)")
    
    # Get high demand wards
    high_demand_wards = get_high_demand_wards(db_conn)
    
    # If we have coordinates for the driver's current ward, use those
    # For a real implementation, you'd store the driver's actual GPS coordinates
    current_ward = driver["current_ward"]
    if current_ward in ward_coordinates:
        driver_lat = ward_coordinates[current_ward]["latitude"]
        driver_lng = ward_coordinates[current_ward]["longitude"]
    else:
        # Fallback to a default location (Bengaluru center)
        driver_lat = 12.9716
        driver_lng = 77.5946
    
    # Find nearest high demand ward
    nearest_ward = find_nearest_high_demand_ward(driver_lat, driver_lng, high_demand_wards)
    
    if not nearest_ward:
        raise HTTPException(status_code=404, detail="No high demand areas found")
    
    # Get recommended roads within the ward
    recommended_roads = get_recommended_roads(nearest_ward["ward_num"], db_conn)
    nearest_ward["recommended_roads"] = recommended_roads
    
    return nearest_ward

@app.get("/update-all-idle-drivers")
def update_all_idle_drivers(db_conn = Depends(get_db_connection)):
    """
    Identify all idle drivers and update the database with recommended wards.
    This endpoint would be called by a scheduled job.
    """
    idle_drivers = get_idle_drivers(db_conn)
    high_demand_wards = get_high_demand_wards(db_conn)
    
    recommendations = []
    
    for driver in idle_drivers:
        current_ward = driver["current_ward"]
        if current_ward in ward_coordinates:
            driver_lat = ward_coordinates[current_ward]["latitude"]
            driver_lng = ward_coordinates[current_ward]["longitude"]
        else:
            # Default location
            driver_lat = 12.9716
            driver_lng = 77.5946
        
        nearest_ward = find_nearest_high_demand_ward(driver_lat, driver_lng, high_demand_wards.copy())
        
        if nearest_ward:
            recommendations.append({
                "driver_id": driver["driver_id"],
                "recommended_ward": nearest_ward["ward_num"],
                "distance_km": nearest_ward["distance_km"]
            })
            
            # In a real implementation, you might update driver_activity table
            # or add to a notifications/recommendations table
    
    return {"recommendations": recommendations}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)