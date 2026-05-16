package app

type Config struct {
	RuntimeRole string
	BackendURL  string
	DataDir     string
	CSVPath     string
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
