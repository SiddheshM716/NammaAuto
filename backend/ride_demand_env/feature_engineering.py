import pandas as pd

# Load the ride data
ride_data = pd.read_csv("ride_data.csv")

# Convert relevant columns to numeric (remove commas and convert to float)
columns_to_convert = ['Cancelled Bookings', 'Bookings']
for col in columns_to_convert:
    ride_data[col] = ride_data[col].astype(str).str.replace(",", "").astype(float)

# Create the Cancellation Impact feature
ride_data['Cancellation Impact'] = (ride_data['Cancelled Bookings'] / ride_data['Bookings']) * 100

# Save the processed data
ride_data.to_csv("processed_ride_data.csv", index=False)

print("Feature engineering completed. Processed file saved as 'processed_ride_data.csv'.")
