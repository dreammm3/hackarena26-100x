import pandas as pd
from datetime import datetime
import os

def export_to_excel(plaid_data, email_data, screen_time_data, output_dir="data_exports"):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{output_dir}/subvampire_data_{timestamp}.xlsx"

    # Create DataFrames
    df_plaid = pd.DataFrame(plaid_data)
    df_email = pd.DataFrame(email_data)
    df_screen = pd.DataFrame(screen_time_data)

    # Save multiple sheets to Excel
    with pd.ExcelWriter(filename, engine='openpyxl') as writer:
        if not df_plaid.empty:
            df_plaid.to_excel(writer, sheet_name='Plaid Transactions', index=False)
        else:
            pd.DataFrame(columns=['Date', 'Merchant Name', 'Amount', 'Category', 'Raw Description', 'Account Name', 'Transaction ID', 'Pending Status']).to_excel(writer, sheet_name='Plaid Transactions', index=False)
            
        if not df_email.empty:
            df_email.to_excel(writer, sheet_name='Email Subscriptions', index=False)
        else:
            pd.DataFrame(columns=['merchant_name','plan','start_date','cancellation_link']).to_excel(writer, sheet_name='Email Subscriptions', index=False)
            
        if not df_screen.empty:
            df_screen.to_excel(writer, sheet_name='Screen Time Usage', index=False)
        else:
            pd.DataFrame(columns=['package_name','minutes_used','date']).to_excel(writer, sheet_name='Screen Time Usage', index=False)

    return filename
