from __future__ import annotations

import ast
import json
import re
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from app.policy import PolicyRequest


CAST_PATTERN = re.compile(r"\((?:string|bool|IResponse|Jwt|JObject)\)")


class ExpressionMap(dict[str, Any]):
    def __init__(self, data: dict[str, Any] | None = None):
        super().__init__()
        for key, value in (data or {}).items():
            self[str(key)] = value

    def __getitem__(self, key: str) -> Any:
        if key in self.keys():
            return super().__getitem__(key)
        lowered = str(key).lower()
        for existing_key, value in self.items():
            if existing_key.lower() == lowered:
                return value
        raise KeyError(key)

    def get(self, key: str, default: Any = None) -> Any:
        try:
            return self[key]
        except KeyError:
            return default

    def GetValueOrDefault(self, key: str, default: Any = "") -> Any:
        return self.get(key, default)


class CalloutBody:
    def __init__(self, content: bytes):
        self._content = content

    def AsJObject(self) -> dict[str, Any]:
        if not self._content:
            return {}
        try:
            payload = json.loads(self._content.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def AsString(self) -> str:
        return self._content.decode("utf-8", errors="replace")


class CalloutResponse:
    def __init__(self, *, status_code: int, headers: dict[str, str], content: bytes, reason: str | None = None):
        self.StatusCode = status_code
        self.Headers = ExpressionMap(headers)
        self.Body = CalloutBody(content)
        self.ReasonPhrase = reason or ""


class JwtValue:
    def __init__(self, claims: dict[str, Any], token: str):
        self.Raw = token
        self.Claims = ExpressionMap(
            {
                key: [str(item) for item in value] if isinstance(value, list) else [str(value)]
                for key, value in claims.items()
                if value is not None
            }
        )
        self.Subject = str(claims.get("sub", ""))
        self.Issuer = str(claims.get("iss", ""))
        audience = claims.get("aud")
        if isinstance(audience, list):
            self.Audiences = [str(item) for item in audience]
        elif audience is None:
            self.Audiences = []
        else:
            self.Audiences = [str(audience)]


@dataclass(frozen=True)
class _ExpressionRequest:
    method: str
    path: str
    headers: ExpressionMap
    query: ExpressionMap
    original_host: str
    ip_address: str

    def headers_get(self, key: str, default: Any = "") -> Any:
        return self.headers.get(key, default)

    def query_get(self, key: str, default: Any = "") -> Any:
        return self.query.get(key, default)


@dataclass(frozen=True)
class _ExpressionResponse:
    status_code: int
    headers: ExpressionMap

    def headers_get(self, key: str, default: Any = "") -> Any:
        return self.headers.get(key, default)


@dataclass(frozen=True)
class ExpressionContext:
    request: _ExpressionRequest
    response: _ExpressionResponse
    variables: ExpressionMap

    def variables_get(self, key: str, default: Any = "") -> Any:
        return self.variables.get(key, default)


ALLOWED_AST_NODES = (
    ast.Expression,
    ast.BoolOp,
    ast.BinOp,
    ast.UnaryOp,
    ast.Compare,
    ast.Call,
    ast.Name,
    ast.Load,
    ast.Attribute,
    ast.Subscript,
    ast.Constant,
    ast.List,
    ast.Tuple,
    ast.Dict,
    ast.And,
    ast.Or,
    ast.Not,
    ast.Eq,
    ast.NotEq,
    ast.Gt,
    ast.GtE,
    ast.Lt,
    ast.LtE,
    ast.In,
    ast.NotIn,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.Mod,
    ast.USub,
    ast.UAdd,
)

ALLOWED_FUNCTIONS = {"split_last", "str", "len"}


def _normalize_request(req: PolicyRequest) -> _ExpressionRequest:
    incoming_host = str(req.variables.get("forwarded_host") or req.variables.get("incoming_host") or "")
    host = incoming_host.split(",", 1)[0].strip()
    if ":" in host and not host.startswith("["):
        host = host.rsplit(":", 1)[0]
    request_headers = req.variables.get("_request_headers")
    if not isinstance(request_headers, dict):
        request_headers = req.headers
    request_query = req.variables.get("_request_query")
    if not isinstance(request_query, dict):
        request_query = req.query
    return _ExpressionRequest(
        method=req.method,
        path=req.path,
        headers=ExpressionMap(request_headers),
        query=ExpressionMap(request_query),
        original_host=host,
        ip_address=str(req.variables.get("client_ip") or ""),
    )


def build_expression_context(req: PolicyRequest) -> ExpressionContext:
    return ExpressionContext(
        request=_normalize_request(req),
        response=_ExpressionResponse(
            status_code=req.response_status_code or 0,
            headers=ExpressionMap(req.response_headers or req.variables.get("_response_headers") or {}),
        ),
        variables=ExpressionMap(req.variables),
    )


def split_last(value: Any, separator: str) -> str:
    text = str(value)
    parts = text.split(separator)
    return parts[-1] if parts else ""


def _strip_outer_expression(text: str) -> str:
    stripped = text.strip()
    if not stripped.startswith("@"):
        return stripped
    stripped = stripped[1:].strip()
    if stripped.startswith("(") and stripped.endswith(")"):
        return stripped[1:-1].strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        return stripped[1:-1].strip()
    return stripped


def _render_interpolated(text: str, context: ExpressionContext) -> str:
    out: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "{" and (i == 0 or text[i - 1] != "{"):
            depth = 1
            j = i + 1
            while j < len(text) and depth:
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                j += 1
            if depth:
                raise ValueError("Unclosed interpolation expression")
            out.append(str(evaluate_apim_expression(text[i + 1 : j - 1], context)))
            i = j
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _translate_expression(expr: str) -> str:
    translated = CAST_PATTERN.sub("", expr)
    translated = re.sub(r"\btrue\b", "True", translated, flags=re.IGNORECASE)
    translated = re.sub(r"\bfalse\b", "False", translated, flags=re.IGNORECASE)
    translated = translated.replace("&&", " and ")
    translated = translated.replace("||", " or ")
    translated = translated.replace("!=", " != ")
    translated = re.sub(r"(?<![=!<>])!(?!=)", " not ", translated)
    translated = translated.replace("context.Request.Headers.GetValueOrDefault", "context.request.headers_get")
    translated = translated.replace("context.Request.Url.Query.GetValueOrDefault", "context.request.query_get")
    translated = translated.replace("context.Request.OriginalUrl.Host", "context.request.original_host")
    translated = translated.replace("context.Request.IpAddress", "context.request.ip_address")
    translated = translated.replace("context.Request.Url.Path", "context.request.path")
    translated = translated.replace("context.Request.Method", "context.request.method")
    translated = translated.replace("context.Response.Headers.GetValueOrDefault", "context.response.headers_get")
    translated = translated.replace("context.Response.StatusCode", "context.response.status_code")
    translated = translated.replace("context.Variables.GetValueOrDefault", "context.variables_get")
    translated = translated.replace("context.Variables[", "context.variables[")
    translated = translated.replace(".Body.As<JObject>()", ".Body.AsJObject()")
    translated = translated.replace(".Body.As<string>()", ".Body.AsString()")
    translated = translated.replace(".Split(", ".split(")
    translated = translated.replace(".StartsWith(", ".startswith(")
    translated = translated.replace(".Trim()", ".strip()")
    translated = translated.replace(".ToString()", "")
    translated = translated.replace(".Last()", "[-1]")
    return translated


def _validate_ast(expression: str) -> None:
    tree = ast.parse(expression, mode="eval")
    for node in ast.walk(tree):
        if not isinstance(node, ALLOWED_AST_NODES):
            raise ValueError(f"Unsupported expression syntax: {type(node).__name__}")
        if isinstance(node, ast.Name):
            if node.id not in {"context", "True", "False"} and node.id not in ALLOWED_FUNCTIONS:
                raise ValueError(f"Unsupported expression name: {node.id}")


def evaluate_apim_expression(expression: str, context: ExpressionContext) -> Any:
    stripped = _strip_outer_expression(expression)
    if stripped.startswith('$"') and stripped.endswith('"'):
        return _render_interpolated(stripped[2:-1], context)

    translated = _translate_expression(stripped)
    _validate_ast(translated)
    return eval(
        translated,
        {"__builtins__": {}},
        {
            "context": context,
            "split_last": split_last,
            "str": str,
            "len": len,
            "True": True,
            "False": False,
        },
    )


def is_apim_expression(value: str) -> bool:
    stripped = value.strip()
    return stripped.startswith("@(") or stripped.startswith("@{")
