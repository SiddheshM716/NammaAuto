import json
import mysql.connector

# Load GeoJSON
with open("BBMP.geojson", "r") as f:
    data = json.load(f)

# Connect to MySQL
conn = mysql.connector.connect(host="localhost", user="root", password="Aadithya@1124", database="nammayattri")
cursor = conn.cursor()

# Insert Wards
for feature in data["features"]:
    ward_num = f"b_{feature['properties']['KGISWardNo']}"  # Convert to b_<number>
    ward_name = feature["properties"]["KGISWardName"]
    coordinates = feature["geometry"]["coordinates"]

    # Convert coordinates to MySQL POLYGON format
    polygon_wkt = f"POLYGON(({', '.join([f'{lon} {lat}' for lon, lat in coordinates[0]])}))"

    sql = "INSERT INTO ward_geo (ward_num, ward_name, geom) VALUES (%s, %s, ST_GeomFromText(%s))"
    cursor.execute(sql, (ward_num, ward_name, polygon_wkt))

conn.commit()
cursor.close()
conn.close()
