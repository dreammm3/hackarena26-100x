import requests
import json

url = "http://localhost:8000/api/user/subscriptions?user_id=static_user_1"
try:
    response = requests.get(url)
    data = response.json()
    for sub in data.get('subscriptions', []):
        print(f"Merchant: {sub['Merchant']}, Rec: {sub.get('recommendation')}")
except Exception as e:
    print(f"Error: {e}")
