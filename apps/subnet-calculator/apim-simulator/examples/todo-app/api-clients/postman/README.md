# Postman Collection

This collection exercises the APIM-backed todo flow end to end:

- health through APIM
- CORS preflight
- missing and invalid subscription key cases
- list, create, toggle, and final list verification

Import [`todo-through-apim.postman_collection.json`](todo-through-apim.postman_collection.json) and
[`local.postman_environment.json`](local.postman_environment.json) into Postman, select the local environment,
and run the requests in order, or run it from the repo root with:

```bash
make test-todo-postman
```

To point the same collection at a different ingress later, edit the environment
variables rather than the request definitions.

For the repo-wide Bruno and Postman workflow, see
[`docs/API-CLIENT-GUIDE.md`](../../../../docs/API-CLIENT-GUIDE.md).
