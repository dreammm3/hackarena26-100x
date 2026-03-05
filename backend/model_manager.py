import os
import joblib
import numpy as np

class ModelManager:
    def __init__(self, models_dir="ai_models"):
        self.models_dir = models_dir
        self.models = {}
        self.is_loaded = False
        
    def load_models(self):
        """Loads .pkl models for XGBoost, Random Forest, and LightGBM if present."""
        if not os.path.exists(self.models_dir):
            print(f"[AI] Models directory {self.models_dir} not found.")
            return False
            
        model_files = {
            'xgboost': 'xgb_model.pkl',
            'random_forest': 'rf_model.pkl',
            'lightgbm': 'lgbm_model.pkl'
        }
        
        for name, filename in model_files.items():
            path = os.path.join(self.models_dir, filename)
            if os.path.exists(path):
                try:
                    self.models[name] = joblib.load(path)
                    print(f"[AI] Successfully loaded {name} model.")
                except Exception as e:
                    print(f"[AI] Error loading {name}: {e}")
            else:
                print(f"[AI] Model {filename} not found — will use Heuristic Ensemble fallback.")
        
        self.is_loaded = len(self.models) > 0
        return self.is_loaded

    def calculate_ghost_score(self, feature_vector: dict) -> (float, list):
        """
        Calculates the Ghost Score (0-100) using 13 behavioral and billing features.
        Returns (score, influential_factors).
        """
        # Feature Mapping
        f = {
            'charge_ratio': feature_vector.get('charge_ratio', 1.0),
            'payment_regularity': feature_vector.get('payment_regularity', 1.0),
            'descriptor_change': feature_vector.get('descriptor_change', 0),
            'screen_time_minutes': feature_vector.get('screen_time_minutes', 0),
            'screen_time_trend': feature_vector.get('screen_time_trend', 0),
            'price_history': feature_vector.get('price_history', 1.0),
            'duplicate_category': feature_vector.get('duplicate_category', 0),
            'seasonal_pattern': feature_vector.get('seasonal_pattern', 0.0),
            'add_on_detected': feature_vector.get('add_on_detected', 0),
            'free_trial_flag': feature_vector.get('free_trial_flag', 0),
            'stop_payment_history': feature_vector.get('stop_payment_history', 0.0),
            'subscription_tenure_months': feature_vector.get('subscription_tenure_months', 1),
            'last_used_days': feature_vector.get('last_used_days', 0)
        }

        factors = []

        if self.is_loaded:
            X = np.array([[v for v in f.values()]])
            predictions = []
            for name, model in self.models.items():
                try:
                    pred = model.predict_proba(X)[0][1] if hasattr(model, 'predict_proba') else model.predict(X)[0]
                    if pred > 1 and pred <= 100: pred /= 100.0
                    predictions.append(pred)
                except:
                    continue
            
            if predictions:
                final_prob = np.mean(predictions)
                # For ML models, we'd typically use SHAP or feature importance here
                # Simplified for this implementation
                if f['last_used_days'] > 30: factors.append("Low Engagement")
                if f['charge_ratio'] < 0.5: factors.append("Trial Conversion Jump")
                return round(float(final_prob * 100), 2), factors

        # --- EXPERT SYSTEM / HEURISTIC FALLBACK ---
        score = 0
        
        # 1. Usage signals (Primary influence)
        if f['last_used_days'] > 60: 
            score += 40
            factors.append("Severe Inactivity")
        elif f['last_used_days'] > 30: 
            score += 20
            factors.append("Recent Abandonment")
        
        if f['screen_time_minutes'] < 10: 
            score += 15
            factors.append("Minimal Usage")
        
        # 2. Billing & Trial signals
        if f['charge_ratio'] < 0.3: 
            score += 15
            factors.append("Price Jump after Trial")
        if f['free_trial_flag'] == 1 and f['last_used_days'] > 14: 
            score += 15
            factors.append("Unused Trial Conversion")
        if f['price_history'] > 1.15: 
            score += 10
            factors.append("Significant Price Hike")
        
        # 3. Redundancy
        if f['duplicate_category'] == 1: 
            score += 10
            factors.append("Category Redundancy")
        
        # 4. Mitigation
        if f['payment_regularity'] > 0.9 and f['screen_time_minutes'] > 60: score -= 20 
        if f['subscription_tenure_months'] > 12: score -= 10
        
        # 5. Seasonal Protection
        if f['seasonal_pattern'] > 0.7:
            score = score * (1 - f['seasonal_pattern'] * 0.5)
            factors.append("Seasonal Usage Pattern")

        final_score = max(0, min(100, score))
        return float(round(final_score, 2)), factors
