import os
import cohere
from dotenv import load_dotenv

load_dotenv()
api_key = os.getenv("COHERE_API_KEY")
print(f"API Key found: {api_key is not None}")
if api_key:
    try:
        co = cohere.Client(api_key)
        response = co.chat(message="Hello, identify yourself.")
        print(f"Response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")
else:
    print("No API Key found in .env")
