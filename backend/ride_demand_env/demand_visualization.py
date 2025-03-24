import pandas as pd
import matplotlib.pyplot as plt

# Load processed data
df = pd.read_csv("processed_ride_data.csv")

# Exclude "Bangalore Total"
df = df[df["Ward"] != "Bangalore Total"]

# Sort by bookings and take the top 20 wards
top_wards = df.sort_values(by="Bookings", ascending=False).head(20)

# Plot ride demand by area
plt.figure(figsize=(12, 6))
plt.bar(top_wards["Ward"], top_wards["Bookings"], color="skyblue")
plt.xlabel("Wards")
plt.ylabel("Total Bookings")
plt.title("Top 20 Wards by Ride Demand")
plt.xticks(rotation=45, ha="right")
plt.grid(axis="y", linestyle="--", alpha=0.7)
plt.show()
