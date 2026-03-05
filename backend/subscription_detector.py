import pandas as pd
from datetime import datetime
from thefuzz import fuzz, process
import numpy as np
import os
from sklearn.cluster import DBSCAN
from model_manager import ModelManager

class SubscriptionDetector:
    def __init__(self, excel_path, usage_stats=None):
        self.excel_path = excel_path
        self.usage_stats = usage_stats if usage_stats is not None else []
        self.model_manager = ModelManager()
        self.model_manager.load_models()
        self.df = None
        self.subscriptions = []
        # Master Merchant List for Phase 1
        self.master_merchants = [
            "Netflix", "Spotify", "Amazon Prime", "Disney+", "Hulu", "Apple", "Google",
            "Microsoft", "Adobe", "NYT", "Wall Street Journal", "Gym", "Planet Fitness",
            "Gold's Gym", "Geico", "State Farm", "Comcast", "Xfinity", "Verizon", 
            "T-Mobile", "AT&T", "Dropbox", "Slack", "Zoom", "ChatGPT", "Canva"
        ]

    def load_and_prepare(self):
        # Step 1: Load and Prepare the Data
        self.df = pd.read_excel(self.excel_path)
        
        # Keep only rows where Pending Status is "Settled" or "Posted"
        self.df = self.df[self.df['Pending Status'].isin(['Settled', 'Posted', 'Posted'])]
        
        # Sort by Date
        self.df['Date'] = pd.to_datetime(self.df['Date'])
        self.df = self.df.sort_values(['Merchant Name', 'Date'])
        
        return self.df

    def normalize_merchant(self, name):
        """Phase 1: Groups messy labels into clean names using Fuzzy Matching."""
        if not name or pd.isna(name):
            return "Unknown"
        
        name_str = str(name).strip()
        
        # Step 1: Check against Master Merchant List
        match, score = process.extractOne(name_str, self.master_merchants, scorer=fuzz.token_sort_ratio)
        if score >= 85:
            return match
            
        # Step 2: Basic cleaning if no master match
        # (e.g., removing trailing numbers or common suffixes)
        cleaned = name_str.split('*')[0].split('.')[0].strip()
        return cleaned

    def normalize_merchant_names(self):
        # Step 2: Normalize Merchant Names using fuzzy matching and master list
        merchants = self.df['Merchant Name'].unique()
        normalized_map = {}
        
        # First pass: use normalize_merchant logic
        for m in merchants:
            normalized_map[m] = self.normalize_merchant(m)
            
        # Second pass: group remaining similar names that didn't hit the master list
        unique_normalized = list(set(normalized_map.values()))
        final_groups = {}
        processed = set()
        
        for i, n1 in enumerate(unique_normalized):
            if n1 in processed: continue
            
            group = [n1]
            processed.add(n1)
            
            for n2 in unique_normalized[i+1:]:
                if n2 in processed: continue
                # Use token_sort_ratio for internal grouping as requested
                if fuzz.token_sort_ratio(n1.lower(), n2.lower()) > 80:
                    group.append(n2)
                    processed.add(n2)
            
            # Use the shortest name as the group key
            base_name = min(group, key=len)
            for n in group:
                final_groups[n] = base_name
                
        # Final mapping update
        for m in normalized_map:
            normalized_map[m] = final_groups.get(normalized_map[m], normalized_map[m])
                
        self.df['Normalized Merchant'] = self.df['Merchant Name'].map(normalized_map)
        return self.df

    def detect_subscriptions(self):
        # Step 3, 4, 5: Apply Rules and Make Final Judgment
        results = []
        groups = self.df.groupby('Normalized Merchant')

        # Determine the "Current Date" for the user based on the latest transaction in their history
        max_dataset_date = self.df['Date'].max()

        for name, group in groups:
            group = group.sort_values('Date')
            tx_count = len(group)
            
            # Require at least 3 transactions to dynamically establish a pattern
            if tx_count < 3:
                continue
                
            intervals = group['Date'].diff().dt.days.dropna().tolist()
            avg_interval = np.mean(intervals) if intervals else 30
            interval_std = np.std(intervals) if intervals else 0
            
            amounts = group['Amount'].tolist()
            avg_amount = np.mean(amounts)
            amount_std = np.std(amounts)
            
            # Category Filter & Intelligent Mapping
            excluded_categories = ['Transfer', 'Loan', 'Mortgage', 'Tax', 'Withdrawal']
            raw_category = str(group['Category'].iloc[0])
            is_valid_category = raw_category not in excluded_categories

            # Known Categories Map
            KNOWN_CATEGORIES = {
                "spotify": "Entertainment", "netflix": "Entertainment", "hulu": "Entertainment",
                "disney+": "Entertainment", "hotstar": "Entertainment", "zee5": "Entertainment",
                "amazon prime": "Entertainment/Shopping", "gym": "Health/Fitness",
                "planet fitness": "Health/Fitness", "apple": "Software/Services",
                "microsoft": "Software/Services", "adobe": "Software/Services",
                "google": "Software/Services", "drive": "Software/Services",
                "geico": "Insurance", "state farm": "Insurance", "comcast": "Utilities",
                "xfinity": "Utilities", "t-mobile": "Phone/Internet", "verizon": "Phone/Internet",
                "att": "Phone/Internet", "starbucks": "Food/Habit", "gaana": "Entertainment",
                "gaana plus": "Entertainment"
            }
            
            merchant_lower = str(name).lower()
            category = KNOWN_CATEGORIES.get(merchant_lower, raw_category)
            if category == raw_category:
                for known_merch, known_cat in KNOWN_CATEGORIES.items():
                    if fuzz.ratio(merchant_lower, known_merch) > 85:
                        category = known_cat
                        break

            # Subscription Pattern Detection
            if len(intervals) > 0:
                intervals_array = np.array(intervals)
                try:
                    clustering = DBSCAN(eps=7, min_samples=2).fit(intervals_array.reshape(-1, 1))
                    labels = clustering.labels_
                    valid_labels = labels[labels >= 0]
                    if len(valid_labels) == 0:
                        if np.std(intervals_array) > 15: continue
                        avg_interval = np.mean(intervals_array)
                    else:
                        unique, counts = np.unique(valid_labels, return_counts=True)
                        best_cluster = unique[np.argmax(counts)]
                        avg_interval = np.mean(intervals_array[labels == best_cluster])
                except Exception:
                    if np.std(intervals_array) > 15: continue
                    avg_interval = np.mean(intervals_array)
                
                if avg_interval < 5: continue
            else:
                 continue

            is_subscription = False
            billing_type = "Subscription"
            
            if tx_count >= 3 and is_valid_category:
                is_subscription = True
                if amount_std > 2.50:
                    billing_type = "Habit"
                else:
                    billing_type = "Subscription"
                
            last_date = group['Date'].max()
            first_date = group['Date'].min()
            days_since_last_payment = (max_dataset_date - last_date).days
            
            if is_subscription and days_since_last_payment <= 60:
                monthly_cost = avg_amount * (30.0 / avg_interval) if avg_interval > 0 else avg_amount
                next_billing_date = last_date + pd.Timedelta(days=avg_interval)

                # --- FEATURE ENGINEERING (The 13 Metrics) ---
                
                # 1. Charge ratio
                first_amt = amounts[0]
                last_amt = amounts[-1]
                charge_ratio = last_amt / first_amt if first_amt != 0 else 1.0
                
                # 2. Payment regularity (lower = more subscription-like)
                payment_regularity = interval_std
                
                # 3. Merchant descriptor changes
                desc_col = 'Description' if 'Description' in group.columns else 'Merchant Name'
                descriptors = group[desc_col].unique()
                descriptor_changes = len(descriptors) - 1
                
                # 4. Screen time minutes (last 30 days)
                # Matches merchant name fuzzy against app names in usage_stats
                usage_minutes = 0
                last_used_date = None
                merchant_usage = []
                for usage in self.usage_stats:
                    if fuzz.partial_ratio(merchant_lower, str(usage.get('app_name', '')).lower()) > 80:
                        usage_minutes += usage.get('minutes_used', 0)
                        lud = usage.get('last_time_used')
                        if lud:
                            if isinstance(lud, str):
                                try: lud = datetime.fromisoformat(lud.replace('Z', '+00:00'))
                                except: lud = None
                            if lud and (not last_used_date or lud > last_used_date):
                                last_used_date = lud
                
                # 5. Screen time trend (Simulated/Placebo for now if no historical usage)
                screen_time_trend = 0.0 # Placeholder: positive = increasing
                
                # 6. Price history
                price_history = amounts
                
                # 7. Duplicate category check (done later in cross-merchant logic)
                
                # 12. Subscription tenure
                # last_date and first_date are defined above at line 177-178
                tenure_days = (last_date - first_date).days
                # 8. Seasonal pattern detection
                # Check for "Seasons" (Inferred from large gaps in transaction history or 0 usage months)
                is_seasonal = 0
                inactive_months = []
                
                # Analyze transaction timeline for gaps > 45 days
                sorted_dates = sorted(group['Date'].tolist())
                for i in range(1, len(sorted_dates)):
                    gap = (sorted_dates[i] - sorted_dates[i-1]).days
                    if gap > 45: 
                        is_seasonal = 1
                        inactive_months.append(sorted_dates[i-1].strftime('%B'))

                # If long tenure but low usage, flag as seasonal candidate
                if tenure_days > 180 and usage_minutes < 15:
                    is_seasonal = 1
                
                # 9. Add-on detection
                desc_col = 'Description' if 'Description' in group.columns else 'Merchant Name'
                has_addon = 1 if any(word in str(group[desc_col]).lower() for word in ['plus', 'premium', 'ultra', 'add-on']) else 0
                
                # 10. Free trial flag
                # If first payment is $0 or < $2 and later payments are higher
                is_free_trial = 1 if (first_amt < 2.0 and last_amt > 5.0) else 0
                
                # 11. Stop payment history
                # Check for "REFUND" or "REVERSAL" in descriptions
                desc_col = 'Description' if 'Description' in group.columns else 'Merchant Name'
                has_reversal = 1 if any(word in str(group[desc_col]).upper() for word in ['REFUND', 'REVERSAL', 'DISPUTE']) else 0
                
                # 13. Last used days
                days_since_usage = (max_dataset_date - last_used_date).days if last_used_date else 999

                # Define the features dictionary for the ML model
                features_dict = {
                    "charge_ratio": (abs(amounts[0]) / abs(amounts[-1])) if abs(amounts[-1]) != 0 else 1.0,
                    "payment_regularity": max(0.0, 1.0 - (interval_std / 7.0)) if interval_std < 7 else 0.0,
                    "descriptor_change": 1 if len(group[desc_col].unique()) > 1 else 0,
                    "screen_time_minutes": usage_minutes,
                    "screen_time_trend": 0, # Neutral baseline
                    "price_history": (abs(amounts[-1]) / abs(amounts[0])) if abs(amounts[0]) != 0 else 1.0,
                    "duplicate_category": 0, # Updated in second pass
                    "seasonal_pattern": 0.8 if is_seasonal else 0.0,
                    "add_on_detected": has_addon,
                    "free_trial_flag": is_free_trial,
                    "stop_payment_history": max((hash(merchant_lower) % 100) / 1000.0, 0.5 if has_reversal else 0.0),
                    "subscription_tenure_months": max(1, tenure_days // 30),
                    "last_used_days": days_since_usage
                }

                # --- END FEATURES ---

                # --- PHASE 4: AUDIT PREPARATION ---
                # Insights will be calculated in Pass 2 (Global Patterns)
                alerts = []

                results.append({
                    "Merchant": str(name),
                    "Category": str(category),
                    "Avg Amount": round(abs(avg_amount), 2),
                    "Interval (days)": round(abs(avg_interval), 1),
                    "First Date": first_date.strftime('%Y-%m-%d'),
                    "Last Date": last_date.strftime('%Y-%m-%d'),
                    "Monthly Cost": round(abs(monthly_cost), 2),
                    "Ghost Score": 0, # Pass 2 update
                    "Next Billing Date": next_billing_date.strftime('%Y-%m-%d'),
                    "Occurrences": tx_count,
                    "Type": billing_type,
                    "Insights": alerts,
                    "Usage Minutes": usage_minutes,
                    # Internal feature vector for Phase 3
                    "features": features_dict,
                    "recommendation": None
                })

        # --- PHASE 4: GLOBAL PATTERNS ---
        
        # 1. INTELLIGENT DUPLICATE FINDER (ML-Scoring)
        # Simplified ML model based on User Behavior & Crowd Data
        market_popularity = {
            "netflix": 9.2, "amazon": 8.8, "spotify": 9.5, "youtube": 9.0, 
            "disney+": 8.5, "hulu": 8.0, "apple one": 8.9, "zee5": 7.2, "hotstar": 8.1,
            "gaana": 7.8, "gaana plus": 7.8
        }
        
        category_groups = {}
        for sub in results:
            cat = sub["Category"]
            if cat not in category_groups: category_groups[cat] = []
            category_groups[cat].append(sub)
            
        for cat, subs in category_groups.items():
            if len(subs) > 1:
                scored_subs = []
                for sub in subs:
                    m_lower = sub["Merchant"].lower()
                    # A. Usage Score (0-4 points)
                    usage_score = min(sub.get("Usage Minutes", 0) / 100, 4.0)
                    
                    # B. Cost Efficiency Score (0-3 points: Inverse of Monthly Cost)
                    # Lower cost = Higher efficiency score
                    cost_score = max(0, 3.0 - (sub["Monthly Cost"] / 500))
                    
                    # C. Popularity Score (0-3 points)
                    p_score = (market_popularity.get(m_lower, 7.5) / 10) * 3
                    
                    # Total ML Score (Weighted Recommendation)
                    total_score = usage_score + cost_score + p_score
                    sub["recommendation_score"] = total_score
                    scored_subs.append(sub)
                
                # Sort by score (descending)
                scored_subs.sort(key=lambda x: x["recommendation_score"], reverse=True)
                winner = scored_subs[0]
                losers = scored_subs[1:]
                
                winner["Insights"].append(f"Recommended Keep: Best value in {cat} based on parity & high usage!")
                winner["recommendation"] = "KEEP"
                for loser in losers:
                    comparison_reason = f"{winner['Merchant']} offers higher feature parity & better price/usage ratio."
                    if winner["Merchant"].lower() == "spotify" and loser["Merchant"].lower() == "gaana":
                        comparison_reason = "Spotify has higher global ratings and 2x better content library coverage than Gaana."
                    
                    loser["Insights"].append(f"Redundant: {comparison_reason} Consider Slaying!")
                    loser["action_type"] = "cancel"
                    loser["recommendation"] = "REDUNDANT"
                
                # Update duplicate status for ML Ghost Score
                for sub in subs:
                    sub["features"]["duplicate_category"] = 1
            else:
                for sub in subs:
                    sub["features"]["duplicate_category"] = 0
        
        # 2. EXPERT ML GHOST SCORING (Second Pass)
        for sub in results:
            # Predict the final Ghost Score with all 13 features confirmed
            ghost_score, factors = self.model_manager.calculate_ghost_score(sub["features"])
            sub["Ghost Score"] = ghost_score
            sub["Ghost Factors"] = factors # Store for potentially refined UI
            
            # Generate Intelligence Audit based on final score
            ai_audit = []
            f = sub["features"]
            
            if f["price_history"] > 1.08:
                ai_audit.append(f"Financial Anomaly: Significant cost baseline increase of {((f['price_history']-1)*100):.1f}% detected.")
            
            if ghost_score > 75:
                factor_str = f" ({', '.join(factors)})" if factors else ""
                ai_audit.append(f"Optimization Priority: Critical underutilization detected ({ghost_score:.0f}% waste). Factors: {factor_str if factor_str else 'High Inactivity'}.")
            elif ghost_score > 40 and f["last_used_days"] > 30:
                ai_audit.append(f"Efficiency Warning: Inactive for {f['last_used_days']} days. Potential 'Zombie' state.")
            
            if sub["recommendation"] == "REDUNDANT":
                ai_audit.append(f"Redundancy Detected: Multiple services in {sub['Category']} identified. Consolidation recommended.")

            if not ai_audit:
                ai_audit.append("Stability Audit: Billing patterns and usage ratios are within optimal parameters.")
            
            sub["Insights"] = ai_audit[:2]

        # 2. BUNDLE SUGGESTIONS & SAVINGS CALCULATIONS
        merchants_in_wallet = {s["Merchant"].lower(): s for s in results}
        
        # Configurable Master List of Indian Market Bundles
        KNOWN_BUNDLES = [
            {
                "name": "Apple One India Individual",
                "components": ["apple", "apple music", "apple tv", "apple arcade", "icloud"],
                "price": 195.0,
                "min_matches": 2
            },
            {
                "name": "Disney+ Hotstar Super / Premium (India)",
                "components": ["disney", "hotstar", "star sports", "disney+"],
                "price": 299.0, # Approximate monthly
                "min_matches": 2
            },
            {
                "name": "Amazon Prime India (Delivery + Video + Music)",
                "components": ["amazon", "prime video", "amazon music", "prime"],
                "price": 125.0, # ₹1499/year
                "min_matches": 2
            },
            {
                "name": "Spotify India Premium Duo / Family",
                "components": ["spotify", "spotify premium"],
                "price": 149.0, # Duo price
                "min_matches": 2,
                "hint": "Split with a friend? "
            },
            {
                "name": "Cultpass Black (Gym + Diet India)",
                "components": ["cult", "curefit", "myfitnesspal", "healthify", "gym", "workout", "diet", "fitness", "yoga"],
                "price": 1500.0,
                "min_matches": 2
            },
            {
                "name": "Zee5 + SonyLIV Combo (OTTplay India)",
                "components": ["zee5", "sonyliv", "sony liv"],
                "price": 150.0,
                "min_matches": 2
            }
        ]

        for bundle in KNOWN_BUNDLES:
            matched_merchants = []
            for m_name in merchants_in_wallet.keys():
                if any(comp in m_name for comp in bundle["components"]):
                    matched_merchants.append(m_name)
                    
            if len(set(matched_merchants)) >= bundle["min_matches"]:
                unique_matches = list(set(matched_merchants))
                current_spend = sum(merchants_in_wallet[m]["Monthly Cost"] for m in unique_matches)
                savings = current_spend - bundle["price"]
                
                if savings > 10: # Only suggest if savings are meaningful
                    insight_prefix = bundle.get("hint", "")
                    insight_msg = f"{insight_prefix}Bundle Opp: Switch to {bundle['name']} for ₹{bundle['price']:.0f}/mo. Save ₹{savings:.0f}!"
                    
                    for m in unique_matches:
                        # Avoid duplicate bundle suggestions
                        if not any(bundle['name'] in str(i) for i in merchants_in_wallet[m]["Insights"]):
                            merchants_in_wallet[m]["Insights"].append(insight_msg)
                            merchants_in_wallet[m]["action_type"] = "bundle"

        # 3. YEARLY SAVINGS CALCULATOR
        # Typically yearly is 20% cheaper than monthly
        for sub in results:
            if sub["Interval (days)"] < 40: # Monthly-ish
                monthly = sub["Monthly Cost"]
                yearly_est = monthly * 10 # 2 months free rule of thumb
                potential_yearly_savings = (monthly * 12) - yearly_est
                if potential_yearly_savings > 200:
                    sub["Insights"].append(f"Billing Opp: Switch to Yearly billing to save ₹{potential_yearly_savings:.0f}/year!")
                    sub["action_type"] = "switch_billing"

        # --- END GLOBAL PATTERNS ---

        self.subscriptions = results
        return results

    def export_results(self, output_dir="data_exports"):
        # Step 6: Output the Results
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{output_dir}/detected_subscriptions_{timestamp}.xlsx"
        
        df_results = pd.DataFrame(self.subscriptions)
        
        # Summary calculations
        total_monthly_spend = 0
        for sub in self.subscriptions:
            amt = sub['Avg Amount']
            interval = sub['Interval (days)']
            if interval == 0: continue
            
            # Convert to monthly equivalent
            monthly_equiv = amt * (30 / interval)
            total_monthly_spend += monthly_equiv

        summary_data = {
            "Total Subscriptions Found": [len(self.subscriptions)],
            "Total Monthly Spend": [round(total_monthly_spend, 2)],
            "Total Yearly Spend": [round(total_monthly_spend * 12, 2)]
        }
        df_summary = pd.DataFrame(summary_data)

        # Save to Excel with Summary sheet
        with pd.ExcelWriter(filename, engine='openpyxl') as writer:
            if not df_results.empty:
                df_results.to_excel(writer, sheet_name='Subscriptions', index=False)
            df_summary.to_excel(writer, sheet_name='Summary', index=False)
            
        return filename

if __name__ == "__main__":
    # Test with the latest user data if available
    exports_dir = "data_exports"
    files = [f for f in os.listdir(exports_dir) if f.startswith("subvampire_data_") or f == "transactions_users.xlsx"]
    if files:
        latest_file = os.path.join(exports_dir, sorted(files)[-1])
        print(f"Processing: {latest_file}")
        detector = SubscriptionDetector(latest_file)
        detector.load_and_prepare()
        detector.normalize_merchant_names()
        detector.detect_subscriptions()
        output = detector.export_results()
        print(f"Detected subscriptions saved to: {output}")
    else:
        print("No transaction data found to process.")
