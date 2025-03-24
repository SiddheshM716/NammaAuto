import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error

# Load the processed dataset
file_path = "processed_ride_data.csv"
df = pd.read_csv(file_path)

# Convert percentage columns to floats
# Convert currency columns to floats
# Convert percentage columns to floats
for col in df.columns:
    if df[col].dtype == 'object':  # Check if the column is text
        df[col] = df[col].str.replace("₹", "").str.replace("%", "").str.replace(",", "").str.strip()

        # Convert to float only if all values are numeric
        if df[col].str.replace(".", "", 1).str.isnumeric().all():
            df[col] = df[col].astype(float)

            # If it's a percentage column, convert to decimal (e.g., 99.1% → 0.991)
            if df[col].max() > 100:  # Heuristic: percentages are usually <= 100
                df[col] = df[col] / 100.0
# Select features and target variable
target = "Bookings"  # Adjust if needed
features = ['Searches', 'Searches which got estimate', 'Searches for Quotes',
            'Searches which got Quotes', 'Completed Trips', 'Search-to-estimate Rate',
            'Estimate-to-search for quotes Rate', 'Quote Acceptance Rate',
            'Quote-to-booking Rate', 'Drivers\' Earnings', 'Average Distance per Trip (km)',
            'Average Fare per Trip', 'Distance Travelled (km)']

df = df.dropna(subset=[target])  # Ensure no missing target values
X = df[features]
y = df[target]

# Split the data
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train the model
model = RandomForestRegressor(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

# Predictions
y_pred = model.predict(X_test)

# Evaluate model performance
mae = mean_absolute_error(y_test, y_pred)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))

print(f"📊 Model Performance:")
print(f"Mean Absolute Error (MAE): {mae:.2f}")
print(f"Root Mean Squared Error (RMSE): {rmse:.2f}")
