import pandas as pd
import geopandas as gpd
import folium
import numpy as np
from folium.plugins import MarkerCluster

# 🚀 Load the ride demand data
try:
    df = pd.read_csv("processed_ride_data.csv")
    print("✅ Ride demand data loaded successfully!")
except FileNotFoundError:
    print("❌ Error: processed_ride_data.csv not found. Check the file path!")
    exit()

# ❌ Exclude "Bangalore Total" row
df = df[df["Ward"] != "Bangalore Total"]

# 🚀 Load Bangalore ward boundaries (GeoJSON)
try:
    ward_map = gpd.read_file("BBMP.geojson")
    print("✅ Bangalore ward boundary data loaded!")
except FileNotFoundError:
    print("❌ Error: BBMP.geojson file not found. Check the file path!")
    exit()

# 🔍 Debug: Check available columns
print("🔍 Ward Map Columns:", ward_map.columns)
print("🔍 Ride Data Columns:", df.columns)

# 🗺️ Ensure CRS is correct (if missing, set to WGS84)
if ward_map.crs is None:
    print("⚠️ Warning: CRS is not set! Assigning EPSG:4326")
    ward_map.set_crs(epsg=4326, inplace=True)

# 🔄 Merge ride demand data with ward boundaries
ward_map = ward_map.merge(df, left_on="KGISWardName", right_on="Ward", how="left")

# 🚨 Fill missing bookings with 0
ward_map["Bookings"] = ward_map["Bookings"].fillna(0)

# 🏆 Normalize Bookings (Optional: Prevents color scale distortion)
ward_map["Bookings_log"] = np.log1p(ward_map["Bookings"])  # log(1 + x) to avoid log(0)

# ✅ Debug: Check if the 'Bookings' column is present
if "Bookings" not in ward_map.columns:
    print("❌ Error: 'Bookings' column missing after merge!")
    exit()
else:
    print("✅ 'Bookings' column found. Sample values:")
    print(ward_map[["KGISWardName", "Bookings"]].head())

# 📍 Define Bangalore city bounding box (Manually set)
bangalore_bounds = [[12.8, 77.45], [13.2, 77.75]]  # Rough bounding box for Bangalore

# 🗺️ Create a folium map centered on Bangalore **with a better zoom level**
m = folium.Map(location=[12.9716, 77.5946], zoom_start=12)

# 🔀 Add dynamic tile layers
folium.TileLayer("OpenStreetMap").add_to(m)
folium.TileLayer("CartoDB positron").add_to(m)
folium.TileLayer("Stamen Toner", attr="Stamen Design").add_to(m)

# 🎨 Define better Choropleth color scale bins
bins = [0, 10000, 50000, 100000, 200000, 500000, 1000000]

# 🔥 Add Choropleth heatmap layer
try:
    choropleth = folium.Choropleth(
        geo_data=ward_map,
        name="Ride Demand Heatmap",
        data=ward_map,
        columns=["KGISWardName", "Bookings"],
        key_on="feature.properties.KGISWardName",
        fill_color="YlOrRd",  # Yellow-Orange-Red scale
        fill_opacity=0.8,
        line_opacity=0.2,
        bins=bins,  # Custom bins for better visibility
        legend_name="Ride Demand Intensity",
    ).add_to(m)
    print("✅ Choropleth heatmap added successfully!")
except Exception as e:
    print("❌ Error adding Choropleth:", e)

# ℹ️ Add popups showing ride demand per ward
for _, row in ward_map.iterrows():
    folium.GeoJsonTooltip(fields=["KGISWardName", "Bookings"]).add_to(choropleth.geojson)

# 🔘 Add layer control (to switch between different map styles)
folium.LayerControl().add_to(m)

# 📍 Fit the map to the **Bangalore city bounding box**
m.fit_bounds(bangalore_bounds)

# 💾 Save the map to an HTML file
m.save("bangalore_city_ride_demand.html")
print("✅ Map saved as 'bangalore_city_ride_demand.html'. Open this file in your browser.")

# Display the map (works in Jupyter Notebook)
m
