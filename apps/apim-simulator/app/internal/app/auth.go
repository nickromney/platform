package app

import (
	"net/http"
	"strings"
)

func subscriptionKey(cfg SubscriptionConfig, r *http.Request) string {
	for _, name := range cfg.HeaderNames {
		if value := r.Header.Get(name); value != "" {
			return value
		}
	}
	for _, name := range cfg.QueryParamNames {
		if value := r.URL.Query().Get(name); value != "" {
			return value
		}
	}
	return ""
}

func lookupSubscription(cfg SubscriptionConfig, key string) (Subscription, bool) {
	for _, sub := range cfg.Items {
		if key == sub.Keys.Primary || key == sub.Keys.Secondary {
			if sub.State == "" {
				sub.State = "active"
			}
			return sub, true
		}
	}
	if ref, ok := cfg.LegacyKeys[key]; ok {
		return Subscription{ID: ref.ID, Name: ref.Name, State: "active"}, true
	}
	return Subscription{}, false
}

func subscriptionBypassed(cfg SubscriptionConfig, r *http.Request) bool {
	for _, condition := range cfg.Bypass {
		value := r.Header.Get(condition.Header)
		if value == "" {
			continue
		}
		if condition.Equals != "" && value == condition.Equals {
			return true
		}
		if condition.StartsWith != "" && strings.HasPrefix(value, condition.StartsWith) {
			return true
		}
	}
	return false
}
