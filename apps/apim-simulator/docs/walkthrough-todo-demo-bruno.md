# APIM Simulator Walkthrough: Bruno Collection Against The Todo Demo

Generated from a live run against the local repository.

The Bruno collection under `examples/todo-app/api-clients/bruno/` exercises the todo API through APIM in the same order documented in `docs/API-CLIENT-GUIDE.md`.

```bash
set -euo pipefail
report="$(mktemp)"
log="$(mktemp)"
env_file="$(mktemp)"
cat >"$env_file" <<BRUNO_ENV
vars {
  apimBaseUrl: $TODO_APIM_BASE_URL
  frontendOrigin: $TODO_FRONTEND_BASE_URL
  subscriptionKey: todo-demo-key
  invalidSubscriptionKey: todo-demo-key-invalid
}
BRUNO_ENV
(cd examples/todo-app/api-clients/bruno && npm exec --yes --package=@usebruno/cli -- bru run --env-file "$env_file" --reporter-json "$report" . >"$log" 2>&1) || { cat "$log"; rm -f "$env_file"; exit 1; }
jq -S '
  def report:
    if type == "array" then .[0] else . end;

  report as $report
  | {
      collection: ($report.collection.name // "todo-demo-bruno"),
      passed_requests: ($report.summary.passedRequests // $report.stats.passed),
      failed_requests: ($report.summary.failedRequests // $report.stats.failed),
      passed_tests: ($report.summary.passedTests // null),
      failed_tests: ($report.summary.failedTests // null),
      requests: [
        $report.results[] | {
          name,
          status,
          tests: (
            (.testResults // .tests // [])
            | map({
                name: (.description // .name // "unnamed"),
                status
              })
          )
        }
      ]
    }
' "$report"
rm -f "$env_file" "$report" "$log"

```

```output
{
  "collection": "todo-demo-bruno",
  "failed_requests": 0,
  "failed_tests": 0,
  "passed_requests": 8,
  "passed_tests": 22,
  "requests": [
    {
      "name": "01 Health Through APIM",
      "status": "pass",
      "tests": [
        {
          "name": "health returns 200",
          "status": "pass"
        },
        {
          "name": "health payload is healthy",
          "status": "pass"
        },
        {
          "name": "apim policy header is present",
          "status": "pass"
        },
        {
          "name": "apim gateway header is present",
          "status": "pass"
        }
      ]
    },
    {
      "name": "02 CORS Preflight",
      "status": "pass",
      "tests": [
        {
          "name": "preflight returns 200",
          "status": "pass"
        },
        {
          "name": "preflight reflects allowed origin",
          "status": "pass"
        }
      ]
    },
    {
      "name": "03 Missing Subscription Key",
      "status": "pass",
      "tests": [
        {
          "name": "missing key returns 401",
          "status": "pass"
        },
        {
          "name": "missing key message is explicit",
          "status": "pass"
        }
      ]
    },
    {
      "name": "04 Invalid Subscription Key",
      "status": "pass",
      "tests": [
        {
          "name": "invalid key returns 401",
          "status": "pass"
        },
        {
          "name": "invalid key message is explicit",
          "status": "pass"
        }
      ]
    },
    {
      "name": "05 List Todos",
      "status": "pass",
      "tests": [
        {
          "name": "list returns 200",
          "status": "pass"
        },
        {
          "name": "list returns items array",
          "status": "pass"
        },
        {
          "name": "list carries policy header",
          "status": "pass"
        }
      ]
    },
    {
      "name": "06 Create Todo",
      "status": "pass",
      "tests": [
        {
          "name": "create returns 201",
          "status": "pass"
        },
        {
          "name": "create returns an id",
          "status": "pass"
        },
        {
          "name": "create preserves title",
          "status": "pass"
        },
        {
          "name": "create carries policy header",
          "status": "pass"
        }
      ]
    },
    {
      "name": "07 Toggle Created Todo",
      "status": "pass",
      "tests": [
        {
          "name": "toggle returns 200",
          "status": "pass"
        },
        {
          "name": "toggle completes the created todo",
          "status": "pass"
        },
        {
          "name": "toggle carries policy header",
          "status": "pass"
        }
      ]
    },
    {
      "name": "08 List After Toggle",
      "status": "pass",
      "tests": [
        {
          "name": "final list returns 200",
          "status": "pass"
        },
        {
          "name": "final list contains the created todo",
          "status": "pass"
        }
      ]
    }
  ]
}
```
