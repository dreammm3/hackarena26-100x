import requests
import time

BASE_URL = "http://127.0.0.1:8000"

def test_plaid():
    data = {
        "amount": 14.99,
        "merchant_name": "Netflix",
        "description": "Netflix Standard Plan",
        "date": "2023-10-01",
        "category": "Entertainment"
    }
    r = requests.post(f"{BASE_URL}/api/plaid/transactions", json=data)
    print("Plaid:", r.json())

def test_email():
    data = {
        "merchant_name": "Spotify",
        "plan": "Premium Individual",
        "start_date": "2023-09-15",
        "cancellation_link": "https://spotify.com/cancel"
    }
    r = requests.post(f"{BASE_URL}/api/email/subscriptions", json=data)
    print("Email:", r.json())

def test_screen_time():
    data = {
        "package_name": "com.netflix.mediaclient",
        "minutes_used": 120,
        "date": "2023-10-02"
    }
    r = requests.post(f"{BASE_URL}/api/usage/sync", json=data)
    print("Screen Time:", r.json())

def trigger_export():
    r = requests.post(f"{BASE_URL}/api/export/excel")
    print("Export:", r.json())

if __name__ == "__main__":
    print("Testing APIs...")
    test_plaid()
    test_email()
    test_screen_time()
    
    print("Triggering Excel Export...")
    trigger_export()
