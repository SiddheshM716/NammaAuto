import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Load cleaned data
ride_data = pd.read_csv("cleaned_ride_data.csv")
ride_data2 = pd.read_csv("cleaned_ride_data2.csv")

# 1. Basic statistics
print("Basic Statistics:")
print(ride_data.describe())
print(ride_data2.describe())

# 2. Plot Demand Trends
plt.figure(figsize=(12, 6))
sns.lineplot(x=ride_data2["datetime"], y=ride_data2["total_fare"])
plt.xticks(rotation=45)
plt.xlabel("Time")
plt.ylabel("Total Fare Collected")
plt.title("Ride Demand Trend Over Time")
plt.show()

# 3. Top Wards by Demand
top_wards = ride_data.nlargest(10, 'Bookings')
plt.figure(figsize=(12, 6))
sns.barplot(x=top_wards['Ward'], y=top_wards['Bookings'])
plt.xticks(rotation=45)
plt.xlabel("Ward")
plt.ylabel("Number of Bookings")
plt.title("Top 10 Wards by Bookings")
plt.show()

# 4. Correlation Matrix
plt.figure(figsize=(12, 8))
sns.heatmap(ride_data.corr(), annot=True, cmap="coolwarm", fmt=".2f", linewidths=0.5)
plt.title("Feature Correlation Matrix")
plt.show()

print("EDA Completed Successfully!")
