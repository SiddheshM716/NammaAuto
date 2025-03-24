import requests
import time
from supabase import create_client, Client

# Supabase Configuration
SUPABASE_URL = "https://vsrafcmvrzprgxsvjwba.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzcmFmY212cnpwcmd4c3Zqd2JhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE4NzQ3MzUsImV4cCI6MjA1NzQ1MDczNX0.wTXpoTTvUDT7DIhatQIxiHihtdD5l9IuxG-a-82R8xw"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Function to fetch data
def fetch_data():
    url = "https://d11gklsvr97l1g.cloudfront.net/open/json-data/trends_live_ward_new_key_purple.json"
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response.json()  # Returns list of dictionaries
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching data: {e}")
        return None

# Insert data into Supabase
def insert_data(data):
    try:
        # Rename API fields to match Supabase table column names
        for record in data:
            record["search_requests"] = record.pop("srch_rqst", None)
            record["searches_got_estimate"] = record.pop("srch_which_got_e", None)
            record["searches_for_quotes"] = record.pop("srch_fr_q", None)
            record["searches_got_quotes"] = record.pop("srch_which_got_q", None)
            record["bookings"] = record.pop("booking", None)
            record["completed_rides"] = record.pop("done_ride", None)
            record["earnings"] = record.pop("earning", None)
            record["cancelled_rides"] = record.pop("cancel_ride", None)
            record["driver_cancel"] = record.pop("drvr_cancel", None)
            record["rider_cancel"] = record.pop("rider_cancel", None)
            record["conversion_rate"] = record.pop("cnvr_rate", None)
            record["booking_cancellation_rate"] = record.pop("bkng_cancel_rate", None)
            record["quote_acceptance_rate"] = record.pop("q_accept_rate", None)
        
        response = supabase.table("ward_demand").insert(data).execute()
        print(f"✅ Inserted {len(data)} records successfully.")
    except Exception as e:
        print(f"❌ Error inserting data: {e}")

# Main loop to fetch and store data every 5 minutes
def main():
    while True:
        print("🔄 Fetching data...")
        data = fetch_data()
        if data:
            insert_data(data)
        print("⏳ Waiting for the next update (5 min)...")
        time.sleep(300)  # Wait for 5 minutes before fetching again

if __name__ == "__main__":
    main()
