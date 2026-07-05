package app

import "platform.local/idpauth"

type principal struct {
	Source  string
	Claims  idpauth.UserClaims
	Session *idpauth.GatewaySession
}

type chatRequest struct {
	Message  string        `json:"message"`
	Model    string        `json:"model,omitempty"`
	Messages []chatMessage `json:"messages,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatResponse struct {
	Assistant      string         `json:"assistant"`
	Model          modelEvidence  `json:"model"`
	Usage          map[string]any `json:"usage,omitempty"`
	Auth           map[string]any `json:"auth"`
	DurationMillis int64          `json:"duration_ms"`
}

type modelEvidence struct {
	Provider       string `json:"provider"`
	Model          string `json:"model"`
	Status         string `json:"status"`
	Route          string `json:"route"`
	UpstreamStatus int    `json:"upstream_status"`
	LatencyMillis  int64  `json:"latency_ms"`
}

type completionResponse struct {
	Model   string         `json:"model"`
	Usage   map[string]any `json:"usage"`
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
		Text string `json:"text"`
	} `json:"choices"`
}

func (r completionResponse) firstContent() string {
	if len(r.Choices) == 0 {
		return ""
	}
	if r.Choices[0].Message.Content != "" {
		return r.Choices[0].Message.Content
	}
	return r.Choices[0].Text
}
