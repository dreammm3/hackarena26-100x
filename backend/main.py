from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Any
from excel_exporter import export_to_excel
import plaid_service
import os
import cohere
from dotenv import load_dotenv

load_dotenv()
COHERE_API_KEY = os.getenv("COHERE_API_KEY")
print(f"[AI] Cohere API Key present: {bool(COHERE_API_KEY)}")
# Use ClientV2 - required for free/trial API keys
co = cohere.ClientV2(COHERE_API_KEY) if COHERE_API_KEY else None

# Try to connect to PostgreSQL, but don't crash if it's unavailable
try:
    from sqlalchemy.orm import Session
    import models
    from database import engine, get_db
    models.Base.metadata.create_all(bind=engine)
    DB_AVAILABLE = True
    print("[DB] PostgreSQL connected successfully.")
except Exception as e:
    DB_AVAILABLE = False
    print(f"[DB] PostgreSQL unavailable ({e}). Running without database — core features still work.")

app = FastAPI(title="NiyamPe API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Temporary in-memory storage for collected data
plaid_data_store = []
email_data_store = []
screen_time_store = []
ghost_address_store = []

# Wallet storage (User ID -> Balance)
user_wallets = {
    "static_user_1": 50.0, # Initial demo balance
    "static_user_2": 1000.0
}

# Sub Management (Mock Storage)
paused_subs = {} # user_id -> { merchant_name: pause_until }
canceled_subs = {} # user_id -> set(merchant_names)

@app.get("/")
def read_root():
    return {"message": "Welcome to NiyamPe API"}

class UsageItem(BaseModel):
    package_name: str
    app_name: str
    minutes_used: int
    last_time_used: str

class UsageSyncRequest(BaseModel):
    usage_data: List[UsageItem]

class LoginRequest(BaseModel):
    email: str
    password: str

@app.post("/api/auth/login")
def login(req: LoginRequest):
    # Mock login for static demo users
    if req.email == "user@example.com" and req.password == "password":
        return {"status": "success", "user_id": "static_user_1", "email": req.email}
    elif req.email == "user2@example.com" and req.password == "password":
        return {"status": "success", "user_id": "static_user_2", "email": req.email}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.get("/api/user/subscriptions")
def get_user_subscriptions(user_id: str = "static_user_1"):
    # Resolve the correct Excel dataset based on the logged-in user
    if user_id == "static_user_2":
        excel_path = "data_exports/transactions_users2.xlsx"
    else:
        excel_path = "data_exports/transactions_users.xlsx"
        
    if not os.path.exists(excel_path):
        raise HTTPException(status_code=404, detail=f"Transaction data not found at {excel_path}")
    
    from subscription_detector import SubscriptionDetector
    
    # NEW: Fetch usage data for AI feature engineering
    usage_data = []
    if DB_AVAILABLE:
        try:
            # For demo, using static user_id 1
            db = next(get_db())
            db_usage = db.query(models.UsageData).filter(models.UsageData.user_id == 1).all()
            usage_data = [{"app_name": u.app_name, "minutes_used": u.minutes_used, "last_time_used": u.last_time_used} for u in db_usage]
        except Exception as e:
            print(f"[AI] Usage fetch failed: {e}")
            usage_data = screen_time_store # Fallback to in-memory
    else:
        usage_data = screen_time_store

    detector = SubscriptionDetector(excel_path, usage_stats=usage_data)
    detector.load_and_prepare()
    detector.normalize_merchant_names()
    subs = detector.detect_subscriptions()
    
    # Apply Pause/Cancel Status
    user_paused = paused_subs.get(user_id, {})
    user_canceled = canceled_subs.get(user_id, set())
    
    import datetime
    now = datetime.datetime.now()
    
    final_subs = []
    for s in subs:
        m_name = s["Merchant"]
        if m_name in user_canceled:
            continue # Don't show canceled subscriptions or flag them as inactive
            
        s["is_paused"] = False
        s["pause_until"] = None
        
        if m_name in user_paused:
            pause_until_str = user_paused[m_name]
            pause_until = datetime.datetime.fromisoformat(pause_until_str)
            if pause_until > now:
                s["is_paused"] = True
                s["pause_until"] = pause_until_str
                s["Monthly Cost"] = 0 # Temporarily stop payment
                s["Insights"].append(f"Paused until {pause_until.strftime('%d %b %Y')}")
            else:
                # Pause expired
                del user_paused[m_name]
        
        final_subs.append(s)
    
    return {"status": "success", "subscriptions": final_subs}

@app.get("/api/email/sync")
def sync_emails():
    try:
        from email_parser import EmailParser
        parser = EmailParser()
        parser.authenticate()
        subs = parser.parse_receipts()
        return {"status": "success", "subscriptions": subs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/plaid/create_link_token")
def create_plaid_link_token(client_user_id: str = "user_123"):
    try:
        token_data = plaid_service.create_link_token(client_user_id)
        if token_data:
            return token_data
        raise HTTPException(status_code=500, detail="Failed to create link token")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class PublicTokenRequest(BaseModel):
    public_token: str

@app.post("/api/plaid/exchange_public_token")
def exchange_plaid_public_token(req: PublicTokenRequest):
    try:
        exchange_data = plaid_service.exchange_public_token(req.public_token)
        if exchange_data:
            access_token = exchange_data['access_token']
            
            # Fetch live transactions instantly from Plaid
            transactions = plaid_service.get_transactions(access_token)
            
            for t in transactions:
                # Map Plaid transaction to the standard 8-column format requested by the user
                plaid_data_store.append({
                    "Date": str(t.get('date')),
                    "Merchant Name": t.get('merchant_name') or t.get('name'),
                    "Amount": t.get('amount'),
                    "Category": t.get('category')[0] if t.get('category') else "Unknown",
                    "Raw Description": t.get('name'),
                    "Account Name": "Plaid Checking", # Simple default for now
                    "Transaction ID": t.get('transaction_id'),
                    "Pending Status": "Posted" if not t.get('pending') else "Pending"
                })
                
            from excel_exporter import export_to_excel
            raw_excel = export_to_excel(plaid_data_store, email_data_store, screen_time_store)
            
            # Step 2: Trigger AI Subscription Detection Engine
            from subscription_detector import SubscriptionDetector
            detector = SubscriptionDetector(raw_excel)
            detector.load_and_prepare()
            detector.normalize_merchant_names()
            detector.detect_subscriptions()
            sub_excel = detector.export_results()
            
            exchange_data['message'] = f"Successfully synced {len(transactions)} real transactions from Plaid! \n\n1. Raw data saved: {raw_excel}\n2. AI Subscriptions detected: {sub_excel}"
            return exchange_data
            
        raise HTTPException(status_code=500, detail="Failed to exchange public token")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class PlaidTransaction(BaseModel):
    amount: float
    merchant_name: str
    description: str
    date: str
    category: str

@app.post("/api/plaid/transactions")
def add_plaid_transaction(tx: PlaidTransaction):
    tx_dict = tx.dict()
    plaid_data_store.append(tx_dict)
    return {"status": "success", "message": "Transaction added"}

@app.get("/api/plaid/data")
def get_plaid_data():
    return {"status": "success", "transactions": plaid_data_store}

class EmailSubscription(BaseModel):
    merchant_name: str
    plan: str
    start_date: str
    cancellation_link: str

@app.post("/api/email/subscriptions")
def add_email_subscription(sub: EmailSubscription):
    sub_dict = sub.dict()
    email_data_store.append(sub_dict)
    return {"status": "success", "message": "Email subscription added"}

class ScreenTimeUsage(BaseModel):
    package_name: str
    minutes_used: int
    date: str

@app.post("/api/usage/sync")
def sync_usage(usage: ScreenTimeUsage):
    usage_dict = usage.dict()
    screen_time_store.append(usage_dict)
    return {"status": "success", "message": "Usage synced"}

@app.post("/api/export/excel")
def trigger_excel_export():
    try:
        filename = export_to_excel(plaid_data_store, email_data_store, screen_time_store)
        return {"status": "success", "message": f"Data exported successfully to {filename}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

import uuid

@app.post("/api/screen-time")
def sync_screen_time(req: UsageSyncRequest, db: Session = Depends(get_db)):
    # Store in memory for immediate access
    for item in req.usage_data:
        screen_time_store.append(item.dict())
        
        # Store in Postgres if available
        if DB_AVAILABLE:
            try:
                # Convert ISO string to datetime
                last_used = datetime.datetime.fromisoformat(item.last_time_used.replace('Z', '+00:00'))
                
                usage_entry = models.UsageData(
                    user_id=1,  # Hardcoded for demo/static user
                    package_name=item.package_name,
                    app_name=item.app_name,
                    minutes_used=item.minutes_used,
                    last_time_used=last_used
                )
                db.add(usage_entry)
                db.commit()
            except Exception as e:
                print(f"[DB] Error saving usage data: {e}")
                db.rollback()

    return {"status": "success", "synced_count": len(req.usage_data)}

@app.post("/api/ghost/generate")
def generate_ghost_address(user_id: str = "static_user_1"):
    unique_id = str(uuid.uuid4())[:8]
    ghost_email = f"ghost-{unique_id}@subslayer.test"
    ghost_address_store.append({
        "user_id": user_id,
        "email_address": ghost_email,
        "active": True
    })
    return {"status": "success", "email_address": ghost_email}

@app.get("/api/ghost/list")
def list_ghost_addresses(user_id: str = "static_user_1"):
    user_ghosts = [g for g in ghost_address_store if g["user_id"] == user_id]
    return {"status": "success", "ghost_addresses": user_ghosts}

@app.get("/api/wallet/balance")
def get_wallet_balance(user_id: str = "static_user_1"):
    return {"status": "success", "balance": user_wallets.get(user_id, 0.0)}

class TopupRequest(BaseModel):
    amount: float

@app.post("/api/wallet/topup")
def topup_wallet(req: TopupRequest, user_id: str = "static_user_1"):
    if user_id not in user_wallets:
        user_wallets[user_id] = 0.0
    user_wallets[user_id] += req.amount
    return {"status": "success", "new_balance": user_wallets[user_id]}

@app.delete("/api/ghost/burn")
def burn_ghost_address(email_address: str):
    global ghost_address_store
    for ghost in ghost_address_store:
        if ghost["email_address"] == email_address:
            ghost["active"] = False
            return {"status": "success", "message": f"Ghost address {email_address} deactivated (burned)."}
    raise HTTPException(status_code=404, detail="Ghost address not found")

class InboundEmailPayload(BaseModel):
    to: str
    sender: str
    subject: str
    body: str

@app.post("/api/ghost/inbound")
def handle_inbound_email(payload: InboundEmailPayload):
    matched_ghost = next((g for g in ghost_address_store if g["email_address"] == payload.to), None)
    if not matched_ghost:
        raise HTTPException(status_code=404, detail="Ghost address not found")
        
    if not matched_ghost.get("active", True):
        return {"status": "blocked", "message": "Email blocked. Ghost address is burned."}
        
    body_lower = payload.body.lower()
    subject_lower = payload.subject.lower()
    
    amount = 0.0
    import re
    amounts = re.findall(r'\$?\d+\.\d{2}', payload.body)
    if amounts:
        try:
             amount = float(amounts[0].replace('$', ''))
        except:
             pass
             
    merchant = payload.sender.split('@')[0] if '@' in payload.sender else payload.sender
    
    # Advanced Pattern Detection
    event_type = "Subscription"
    notes = f"Detected via Ghost: {payload.subject}"
    
    if any(word in body_lower or word in subject_lower for word in ['cancel', 'terminated', 'refunded']):
        event_type = "Cancellation"
        notes = "Ghost Alert: Cancellation email received."
    elif any(word in body_lower or word in subject_lower for word in ['upgrade', 'premium', 'ultra', 'plan changed']):
        event_type = "Upgrade"
        notes = "Ghost Alert: Plan upgrade/change detected."
    elif any(word in body_lower or word in subject_lower for word in ['price change', 'updated pricing', 'billing update']):
        event_type = "Price Hike"
        notes = "Ghost Alert: Billing policy or price change found."
    elif any(word in body_lower or word in subject_lower for word in ['receipt', 'invoice', 'thanks for your order', 'payment confirmed']):
        event_type = "Receipt"
        notes = "Ghost Alert: New receipt/invoice captured."

    if amount > 0 or event_type != "Subscription":
        # Wallet deduction logic for Ghost Trials
        u_id = matched_ghost.get("user_id", "static_user_1")
        if amount > 0:
            if user_wallets.get(u_id, 0) < amount:
                return {"status": "failed", "message": f"Insufficient wallet balance (₹{user_wallets.get(u_id,0)}) to pay ₹{amount} for {merchant}."}
            user_wallets[u_id] -= amount
            notes += f" | Paid via Wallet (Remaining: ₹{user_wallets[u_id]:.2f})"

        email_data_store.append({
            "Merchant": f"{merchant} (Ghost)",
            "Category": "Software/Services",
            "Avg Amount": amount,
            "Interval (days)": 30,
            "First Date": "2026-01-01",
            "Last Date": datetime.datetime.now().strftime("%Y-%m-%d"),
            "Monthly Cost": amount,
            "Next Billing Date": "See Dashboard",
            "Occurrences": 1,
            "Type": event_type,
            "Insights": [notes]
        })
        return {"status": "success", "message": f"Captured {event_type} for {merchant}. Wallet Balance: ₹{user_wallets.get(u_id,0):.2f}", "event": event_type}
        
    return {"status": "success", "message": "Email received but no actionable sub data found"}

class PauseRequest(BaseModel):
    merchant_name: str
    duration_months: int = 1
    until_date: str = None # ISO format

@app.post("/api/subscriptions/pause")
def pause_subscription(req: PauseRequest, user_id: str = "static_user_1"):
    if user_id not in paused_subs:
        paused_subs[user_id] = {}
    
    import datetime
    if req.until_date:
        pause_until = datetime.datetime.fromisoformat(req.until_date)
    else:
        pause_until = datetime.datetime.now() + datetime.timedelta(days=30 * req.duration_months)
        
    paused_subs[user_id][req.merchant_name] = pause_until.isoformat()
    return {"status": "success", "message": f"{req.merchant_name} paused until {pause_until.strftime('%Y-%m-%d')}"}

class CancelRequest(BaseModel):
    merchant_name: str

@app.post("/api/subscriptions/cancel")
def cancel_subscription(req: CancelRequest, user_id: str = "static_user_1"):
    if user_id not in canceled_subs:
        canceled_subs[user_id] = set()
    canceled_subs[user_id].add(req.merchant_name)
    return {"status": "success", "message": f"{req.merchant_name} canceled immediately."}

class ChatRequest(BaseModel):
    message: str
    subscriptions: List[Dict[str, Any]]

@app.post("/api/ai/chat")
def ai_chat(req: ChatRequest):
    safe_msg = req.message.encode('ascii', 'replace').decode('ascii')
    print(f"[AI] Received chat request from user. Message: {safe_msg[:100]}...")
    if not co:
        print("[AI] Error: Cohere client not initialized. Check COHERE_API_KEY.")
        raise HTTPException(status_code=500, detail="AI Assistant currently unavailable (API Key missing)")
    
    try:
        # Construct context from subscriptions
        print(f"[AI] Preparing context for {len(req.subscriptions)} subscriptions...")
        context = "The user has the following subscriptions:\n"
        for sub in req.subscriptions:
            merchant = sub.get('Merchant', 'Unknown')
            cost = sub.get('Monthly Cost', '0')
            sub_type = sub.get('Type', 'Standard')
            next_billing = sub.get('Next Billing Date', 'N/A')
            insights_list = sub.get('Insights', [])
            insights_str = ", ".join(insights_list) if isinstance(insights_list, list) else str(insights_list)
            context += f"- {merchant}: Rs.{cost} ({sub_type}). Next billing: {next_billing}. Insights: {insights_str}\n"
        
        system_prompt = f"""You are 'Slayer AI', a helpful and proactive subscription assistant for the SubVampire Slayer app. 
Your goal is to help users manage their subscriptions, save money, and find better deals.
Be concise, friendly, and data-driven.
{context}
Answer the user's question based on this data. If they ask for recommendations, suggest pausing or canceling unused subs or switching to yearly plans if beneficial."""

        print(f"[AI] Sending request to Cohere using ClientV2 with model='command-r-08-2024'...")
        # Using ClientV2 with messages format (required for free trial keys)
        response = co.chat(
            model='command-r-08-2024',
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": req.message}
            ]
        )
        
        reply_text = response.message.content[0].text
        safe_reply = reply_text.encode('ascii', 'replace').decode('ascii')
        print(f"[AI] Successfully received response from Cohere: {safe_reply[:50]}...")
        return {"status": "success", "reply": reply_text}
    except Exception as e:
        print(f"[AI] Critical Error during chat: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"AI Error: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
