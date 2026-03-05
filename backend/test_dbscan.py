from subscription_detector import SubscriptionDetector
import numpy as np
from sklearn.cluster import DBSCAN

d = SubscriptionDetector('data_exports/transactions_users2.xlsx')
d.load_and_prepare()
d.normalize_merchant_names()

for name, group in d.df.groupby('Merchant Name'):
    if 'Netflix' not in name: continue
    group = group.sort_values('Date')
    intervals = group['Date'].diff().dt.days.dropna().tolist()
    
    intervals_array = np.array(intervals).reshape(-1, 1)
    clustering = DBSCAN(eps=7, min_samples=2).fit(intervals_array)
    labels = clustering.labels_
    
    valid_labels = labels[labels >= 0]
    if len(valid_labels) == 0:
        print(f"{name}: ALL NOISE")
        continue
        
    unique, counts = np.unique(valid_labels, return_counts=True)
    best_cluster = unique[np.argmax(counts)]
    
    cluster_intervals = intervals_array[labels == best_cluster]
    avg_interval = np.mean(cluster_intervals)
    
    
    max_dataset_date = d.df['Date'].max()
    last_date = group['Date'].max()
    days_since_last_payment = (max_dataset_date - last_date).days
    
    print(f"Name: {name}")
    print(f"Intervals: {intervals}")
    print(f"Labels: {labels}")
    print(f"Best Cluster: {best_cluster} -> avg {avg_interval}")
    print(f"Days since last payment: {days_since_last_payment} (max config is 60)")
    
    # check category
    excluded_categories = ['Transfer', 'Loan', 'Mortgage', 'Tax', 'Withdrawal']
    raw_category = str(group['Category'].iloc[0])
    is_valid_category = raw_category not in excluded_categories
    print(f"Category: {raw_category}, is_valid: {is_valid_category}")
    break
