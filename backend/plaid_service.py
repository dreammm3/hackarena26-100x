import plaid
from plaid.api import plaid_api
from plaid.model.item_public_token_exchange_request import ItemPublicTokenExchangeRequest
from plaid.model.link_token_create_request import LinkTokenCreateRequest
from plaid.model.link_token_create_request_user import LinkTokenCreateRequestUser
from plaid.model.products import Products
from plaid.model.transactions_get_request import TransactionsGetRequest
from plaid.model.transactions_get_request_options import TransactionsGetRequestOptions
from plaid.model.country_code import CountryCode
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv

load_dotenv()

PLAID_CLIENT_ID = os.getenv('PLAID_CLIENT_ID')
PLAID_SECRET = os.getenv('PLAID_SECRET')
PLAID_ENV = os.getenv('PLAID_ENV', 'sandbox')

configuration = plaid.Configuration(
    host=plaid.Environment.Sandbox,
    api_key={
        'clientId': PLAID_CLIENT_ID,
        'secret': PLAID_SECRET,
    }
)

api_client = plaid.ApiClient(configuration)
client = plaid_api.PlaidApi(api_client)

def create_link_token(client_user_id: str):
    request = LinkTokenCreateRequest(
        products=[Products("transactions")],
        client_name="NiyamPe",
        country_codes=[CountryCode("US")],
        language='en',
        user=LinkTokenCreateRequestUser(
            client_user_id=client_user_id
        )
    )
    
    try:
        response = client.link_token_create(request)
        return response.to_dict()
    except plaid.ApiException as e:
        print(f"Plaid Error: {e}")
        return None

def exchange_public_token(public_token: str):
    request = ItemPublicTokenExchangeRequest(
        public_token=public_token
    )
    try:
        response = client.item_public_token_exchange(request)
        return response.to_dict()
    except plaid.ApiException as e:
        print(f"Plaid Error: {e}")
        return None

def get_transactions(access_token: str):
    start_date = (datetime.now() - timedelta(days=365)).date()
    end_date = datetime.now().date()
    
    request = TransactionsGetRequest(
        access_token=access_token,
        start_date=start_date,
        end_date=end_date,
        options=TransactionsGetRequestOptions(
            count=500,
            offset=0
        )
    )
    
    try:
        response = client.transactions_get(request)
        return response.to_dict().get('transactions', [])
    except plaid.ApiException as e:
        print(f"Plaid Error fetching transactions: {e}")
        return []
