import pandas as pd
from datetime import datetime, timedelta
import os

path = 'data_exports/transactions_users.xlsx'
if os.path.exists(path):
    df = pd.read_excel(path)
    df['Date'] = pd.to_datetime(df['Date'])
    last_date = df['Date'].max()
    
    new_rows = []
    # Current date for fresh tracking
    now = datetime.now()
    
    for i in range(4):
        # Generate 4 monthly transactions for Gaana
        date = now - timedelta(days=30*i)
        new_rows.append({
            'Date': date,
            'Amount': 99.0,
            'Merchant Name': 'Gaana Plus',
            'Category': 'Entertainment',
            'User ID': 1
        })
    
    for i in range(4):
        date = now - timedelta(days=30*i)
        new_rows.append({
            'Date': date,
            'Amount': 119.0,
            'Merchant Name': 'Spotify Premium',
            'Category': 'Entertainment',
            'User ID': 1
        })

    # NEW: Indian Bundle Triggers
    # 1. Disney + Hotstar Bundle
    for i in range(4):
        date = now - timedelta(days=30*i)
        new_rows.append({'Date': date, 'Amount': 149.0, 'Merchant Name': 'Disney Plus', 'Category': 'Entertainment', 'User ID': 1})
        new_rows.append({'Date': date, 'Amount': 299.0, 'Merchant Name': 'Hotstar', 'Category': 'Entertainment', 'User ID': 1})

    # 2. OTTplay Combo (Zee5 + SonyLIV)
    for i in range(4):
        date = now - timedelta(days=30*i)
        new_rows.append({'Date': date, 'Amount': 199.0, 'Merchant Name': 'Zee5', 'Category': 'Entertainment', 'User ID': 1})
        new_rows.append({'Date': date, 'Amount': 249.0, 'Merchant Name': 'SonyLIV', 'Category': 'Entertainment', 'User ID': 1})

    df_new = pd.concat([df, pd.DataFrame(new_rows)], ignore_index=True)
    df_new.to_excel(path, index=False)
    print("Gaana, Spotify, Disney+, Hotstar, Zee5, and SonyLIV data added for bundle testing.")
else:
    print(f"File not found: {path}")
