from pydantic import BaseModel, Field

from app.environment_requests import DEFAULT_ENVIRONMENT_ACTION, DEFAULT_ENVIRONMENT_TYPE, ENVIRONMENT_ACTION_PATTERN


class RuntimeInfo(BaseModel):
    name: str
    description: str


class EnvironmentRequest(BaseModel):
    runtime: str
    action: str = Field(default=DEFAULT_ENVIRONMENT_ACTION, pattern=ENVIRONMENT_ACTION_PATTERN)
    app: str = Field(min_length=1)
    environment: str = Field(min_length=1)
    environment_type: str = DEFAULT_ENVIRONMENT_TYPE


class DeploymentRequest(BaseModel):
    runtime: str
    app: str = Field(min_length=1)
    environment: str = Field(min_length=1)
    image: str = ""


class ScaffoldRequest(BaseModel):
    runtime: str
    app: str = Field(min_length=1)
    owner: str = Field(min_length=1)


class SecretRequest(BaseModel):
    runtime: str
    app: str = Field(min_length=1)
    environment: str = Field(min_length=1)
    secret: str = Field(min_length=1)
    keys: list[str] = Field(min_length=1)


class DryRunPlan(BaseModel):
    dry_run: bool = True
    runtime: str
    summary: str
    commands: list[str]
    manifests: list[str] = Field(default_factory=list)


class AuditRecord(BaseModel):
    id: str
    event: str
    runtime: str


class WorkflowResponse(BaseModel):
    dry_run: bool = True
    runtime: str
    workflow: str
    plan: DryRunPlan
    audit: AuditRecord
