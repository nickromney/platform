TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
TG_PLAN_FLAGS ?=
TG_APPLY_FLAGS ?=

# Shared provider plugin cache. `make reset` deletes $(STACK_DIR)/.terraform, so
# without this every rebuild re-downloads the whole provider set (~280MB) before
# the next apply can begin. Provider binaries are content-addressed and pinned by
# .terraform.lock.hcl, so they are safe to keep across a reset -- the lock file is
# still what decides which versions are allowed. The cache lives at the repo root
# rather than under $(STACK_DIR)/.run, which reset also removes.
# Set TF_PLUGIN_CACHE_DIR= (empty) to opt out and restore per-run downloads.
TF_PLUGIN_CACHE_DIR ?= $(REPO_ROOT)/.run/tofu-plugin-cache

# Expands to a `mkdir -p ... && ` prefix; OpenTofu errors if the cache directory
# named by TF_PLUGIN_CACHE_DIR does not already exist.
tg_plugin_cache_prepare = $(if $(TF_PLUGIN_CACHE_DIR),mkdir -p "$(TF_PLUGIN_CACHE_DIR)" && ,)

TG_ENV_PREFIX = $(if $(TF_PLUGIN_CACHE_DIR),TF_PLUGIN_CACHE_DIR="$(TF_PLUGIN_CACHE_DIR)" ,)TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS)

define tg_stack_init
$(tg_plugin_cache_prepare)cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) init $(TG_INIT_FLAGS)
endef

define tg_stack_plan
$(tg_plugin_cache_prepare)cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) plan $(TG_PLAN_FLAGS) $(strip $(1))
endef

define tg_stack_apply
$(tg_plugin_cache_prepare)cd "$(STACK_DIR)" && $(TG_ENV_PREFIX) $(TG) apply $(TG_APPLY_FLAGS) $(strip $(1))
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
