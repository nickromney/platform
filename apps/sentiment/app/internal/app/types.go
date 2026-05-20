package app

import "errors"

var ErrInvalidToken = errors.New("invalid bearer token")

type Config struct {
	AuthMode        string
	APIAuthMode     string
	RuntimeRole     string
	BackendURL      string
	APIBasePath     string
	OIDCIssuer      string
	OIDCAudience    string
	OIDCJWKSURI     string
	DataDir         string
	CSVPath         string
	NetworkHops     string
	ShowNetworkPath string
}

type UserClaims struct {
	Subject           string   `json:"sub"`
	PreferredUsername string   `json:"preferred_username,omitempty"`
	Email             string   `json:"email,omitempty"`
	Groups            []string `json:"groups"`
}

type Label string

const (
	Positive Label = "positive"
	Negative Label = "negative"
	Neutral  Label = "neutral"
)

type Comment struct {
	ID         string  `json:"id"`
	Timestamp  string  `json:"timestamp"`
	Text       string  `json:"text"`
	Label      Label   `json:"label"`
	Confidence float64 `json:"confidence"`
	LatencyMS  int64   `json:"latency_ms"`
}

type classifyRequest struct {
	Text string `json:"text"`
}

type classifyResponse struct {
	Text       string  `json:"text"`
	Label      Label   `json:"label"`
	Confidence float64 `json:"confidence"`
	LatencyMS  int64   `json:"latency_ms"`
}

type errorResponse struct {
	Error string `json:"error"`
}
