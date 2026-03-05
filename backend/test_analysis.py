import pandas as pd
df = pd.read_excel('data_exports/transactions_users.xlsx')
df['Date'] = pd.to_datetime(df['Date'])
for name, group in df.groupby('Merchant Name'):
    if len(group) > 5:
        group = group.sort_values('Date')
        intervals = group['Date'].diff().dt.days.dropna()
        print(f'{name}: {len(group)} txns, interval: mean={intervals.mean():.1f}, std={intervals.std():.1f}, amount: mean={group["Amount"].mean():.1f}, std={group["Amount"].std():.1f}')
