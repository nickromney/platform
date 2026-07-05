# Auth Chat

Small Go single page app for proving the platform auth/chat shape locally:

- `GET /auth` returns the current gateway or bearer-token identity evidence.
- `POST /auth/validate` checks the same auth contract without sending a chat.
- `POST /chat` requires the local auth contract and calls an OpenAI-compatible
  model endpoint.

The browser UI is dependency-free HTML/CSS/JavaScript embedded in the Go binary.
It reuses the shared platform app shell, shared IDP browser helper, and shared
HTTP helpers.

## Local Run

Run the app directly against a host oMLX endpoint:

```sh
AUTH_CHAT_LLM_URL=http://127.0.0.1:8000/v1/chat/completions \
AUTH_CHAT_LLM_MODEL=Qwen3.5-9B-MLX-4bit \
  make -C apps/auth-chat app-run
```

Open `http://localhost:18086`.

For the Kubernetes SSO path, stage 900 routes
`https://auth-chat.dev.127.0.0.1.sslip.io` through Keycloak and oauth2-proxy.

## Tests

```sh
make -C apps/auth-chat/app test
make -C apps/auth-chat/app js-check
```
