TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
TG_PLAN_FLAGS ?=
TG_APPLY_FLAGS ?=

TG_ENV_PREFIX = TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS)

define tg_stack_init
cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) init $(TG_INIT_FLAGS)
endef

define tg_stack_plan
cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) plan $(TG_PLAN_FLAGS) $(strip $(1))
endef

define tg_stack_apply
cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) apply $(TG_APPLY_FLAGS) $(strip $(1))
endef
