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

# Ordered tfvar files for every plan/apply/check site.
# Recursive `=` so this expands at recipe exec, after the variant adapter
# defines stage_var_file / target_var_file and stage-workflow.mk sets
# STAGE_SPECIFIED. kind sets profile + operator; lima leaves both empty.
#
# stack_tfvar_args omits the stage file unless the operator named a stage
# (diagnostic/check targets). stack_tfvar_args_full always includes it, for
# plan/apply/readiness helpers that default STAGE=100 even when STAGE_SPECIFIED
# is unset.
stack_tfvar_profile ?=
stack_tfvar_operator ?=
stack_tfvar_common = --optional-file "$(target_var_file)" \
	$(stack_tfvar_profile) \
	--optional-file "$${PLATFORM_BASE_TFVARS:-}" \
	--optional-file "$${PLATFORM_TFVARS:-}" \
	$(stack_tfvar_operator)
stack_tfvar_args = $(if $(filter 1,$(STAGE_SPECIFIED)),--optional-file "$(stage_var_file)") \
	$(stack_tfvar_common)
stack_tfvar_args_full = --optional-file "$(stage_var_file)" \
	$(stack_tfvar_common)
