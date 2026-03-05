import httpx

BASE_URL = "http://127.0.0.1:8000"

def test_plaid_link_token():
    print("Testing Plaid Link Token Generation...")
    try:
        response = httpx.post(f"{BASE_URL}/api/plaid/create_link_token?client_user_id=test_user_1")
        print(f"Status: {response.status_code}")
        print("Response JSON:")
        print(response.json())
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_plaid_link_token()
