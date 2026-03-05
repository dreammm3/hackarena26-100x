import os
import pickle
import re
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from bs4 import BeautifulSoup
import base64

# If modifying these scopes, delete the file token.pickle.
# Using readonly scope to ensure we don't accidentally modify emails.
SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']
CREDENTIALS_FILE = 'credentials.json'
TOKEN_FILE = 'token.pickle'

class EmailParser:
    def __init__(self):
        self.service = None

    def authenticate(self):
        """Shows basic usage of the Gmail API.
        Lists the user's Gmail labels.
        """
        creds = None
        # The file token.pickle stores the user's access and refresh tokens, and is
        # created automatically when the authorization flow completes for the first
        # time.
        if os.path.exists(TOKEN_FILE):
            with open(TOKEN_FILE, 'rb') as token:
                creds = pickle.load(token)
                
        # If there are no (valid) credentials available, let the user log in.
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                if not os.path.exists(CREDENTIALS_FILE):
                    raise FileNotFoundError(f"Missing {CREDENTIALS_FILE} - Please download it from Google Cloud Console.")
                    
                flow = InstalledAppFlow.from_client_secrets_file(
                    CREDENTIALS_FILE, SCOPES)
                creds = flow.run_local_server(port=0)
                
            # Save the credentials for the next run
            with open(TOKEN_FILE, 'wb') as token:
                pickle.dump(creds, token)

        self.service = build('gmail', 'v1', credentials=creds)
        print("Successfully authenticated with Gmail API.")
        
    def search_messages(self, query):
        if not self.service:
            raise Exception("Gmail API not authenticated. Call authenticate() first.")
            
        try:
            results = self.service.users().messages().list(userId='me', q=query, maxResults=50).execute()
            messages = results.get('messages', [])
            return messages
        except Exception as error:
            print(f"An error occurred: {error}")
            return []
            
    def fetch_message_details(self, msg_id):
        try:
            message = self.service.users().messages().get(userId='me', id=msg_id, format='full').execute()
            payload = message.get('payload', {})
            headers = payload.get('headers', [])
            
            subject = ""
            sender = ""
            date = ""
            for header in headers:
                if header['name'] == 'Subject':
                    subject = header['value']
                elif header['name'] == 'From':
                    sender = header['value']
                elif 'Date' in header['name']:
                    date = header['value']
                    
            # The email might be multipart or simple
            body = self._extract_body(payload)
            return {"body": body, "subject": subject, "sender": sender, "date": date}
        except Exception as error:
            print(f"An error occurred: {error}")
            return None

    def _extract_body(self, payload):
        body = ""
        if 'parts' in payload:
            for part in payload['parts']:
                if part['mimeType'] == 'text/plain':
                    data = part['body'].get('data')
                    if data:
                        body += base64.urlsafe_b64decode(data).decode('utf-8')
                elif part['mimeType'] == 'text/html':
                    data = part['body'].get('data')
                    if data:
                        # Extract HTML text via BeautifulSoup
                        html = base64.urlsafe_b64decode(data).decode('utf-8')
                        soup = BeautifulSoup(html, 'html.parser')
                        body += soup.get_text(separator=' ')
                elif 'parts' in part:
                    body += self._extract_body(part) # Recursive call
        else:
             data = payload['body'].get('data')
             if data:
                 if payload.get('mimeType') == 'text/html':
                     html = base64.urlsafe_b64decode(data).decode('utf-8')
                     soup = BeautifulSoup(html, 'html.parser')
                     body += soup.get_text(separator=' ')
                 else:
                     body += base64.urlsafe_b64decode(data).decode('utf-8')
                     
        return body

    def parse_receipts(self):
        query = "subject:receipt OR subject:invoice OR subject:subscription OR subject:renewal"
        messages = self.search_messages(query)
        detected_subs = []
        
        from email.utils import parsedate_to_datetime
        from datetime import datetime
        
        for msg in messages[:20]: # Limit to 20 for speed
            details = self.fetch_message_details(msg['id'])
            if details and details['body']:
                body = details['body']
                sender = details['sender']
                date_str = details['date']
                subject = details['subject']
                
                # Simple heuristic to extract monetary amounts
                amounts = re.findall(r'\$?\d+\.\d{2}', body)
                
                # Try to extract a merchant name from Sender. Format usually: "Netflix" <info@netflix.com>
                merchant_match = re.search(r'^(.*?)\s*<', sender)
                if merchant_match:
                    merchant = merchant_match.group(1).replace('"', '').strip()
                else:
                    merchant = sender.split('@')[0] if '@' in sender else sender

                if not merchant:
                    merchant = "Unknown Email Sender"
                    
                # Try to parse date
                try:
                    if date_str:
                        parsed_date = parsedate_to_datetime(date_str).date()
                        formatted_date = parsed_date.strftime('%Y-%m-%d')
                    else:
                        formatted_date = datetime.now().strftime('%Y-%m-%d')
                except Exception:
                    formatted_date = datetime.now().strftime('%Y-%m-%d')
                
                if amounts:
                    # Clean up amount string
                    amt_str = amounts[0].replace('$', '')
                    try:
                        amt_val = float(amt_str)
                        if amt_val > 0:
                            detected_subs.append({
                                "Merchant": f"{merchant} (via Gmail)",
                                "Category": "Software/Services",
                                "Avg Amount": amt_val,
                                "Interval (days)": 30, # Defaulting to monthly
                                "First Date": formatted_date,
                                "Last Date": formatted_date,
                                "Monthly Cost": amt_val,
                                "Next Billing Date": "Unknown",
                                "Occurrences": 1,
                                "Notes": f"Detected from Gmail: {subject}"
                            })
                    except ValueError:
                        pass
                        
        return detected_subs

if __name__ == '__main__':
    # Test block
    try:
        parser = EmailParser()
        parser.authenticate()
        print("Authentication Setup Good!")
    except FileNotFoundError as e:
        print(f"Waiting for credentials: {e}")
