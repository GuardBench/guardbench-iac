#!/usr/bin/env bash
# Host launcher: provision/bootstrap separately, then invoke the image's runner.
set -euo pipefail

runner_root=${GUARDBENCH_RUNNER_ROOT:-/opt/guardbench-performance-runner}
fail() { printf '%s\n' "$*" >&2; exit 1; }
for argument in "$@"; do
  case "$argument" in
    --reset|--reset=*) fail 'DB reset is not supported. Use a Backend #212 compatible Runner image.' ;;
    --result-dir|--result-dir=*) fail 'Results are managed by this launcher under results/.' ;;
  esac
done
exec 9>"$runner_root/execution.lock"
flock -n 9 || fail 'Another performance execution is already using this runner.'

runner_image=$(<"$runner_root/image")
expected_digest=$(<"$runner_root/expected-digest")
[[ "$expected_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail 'Invalid pinned Runner digest; rerun bootstrap.'
[[ "$runner_image" == "$(<"$runner_root/expected-image")" ]] || fail 'Runner image metadata mismatch; rerun bootstrap.'
image_reference="${runner_image%:*}@$expected_digest"
docker image inspect "$image_reference" >/dev/null

# Reject legacy reset/migration code before making any workload/API requests.
# Do not execute the old verify-runtime: it invokes Gradle and requires SQL/Java.
docker run --rm -i --entrypoint python3.11 "$image_reference" - <<'PY'
import ast
from pathlib import Path
source = Path('/workspace/performance/runner/cli.py').read_text()
tree = ast.parse(source)
legacy_calls = {'reset_database', 'apply_migrations'}
for node in ast.walk(tree):
    if isinstance(node, ast.Call):
        name = getattr(node.func, 'id', getattr(node.func, 'attr', ''))
        if name in legacy_calls:
            raise SystemExit('Runner image still calls DB reset/migration. Publish Backend #212, update performance_runner_image_tag, apply, and rerun bootstrap.')
PY

environment_value() {
  local value
  value=$(sed -n "s/^$1=//p" "$runner_root/environment")
  [[ "$value" =~ [^[:space:]] && "$value" != *$'\n'* ]] || fail "Missing or invalid environment: $1"
  printf '%s' "$value"
}
region=$(environment_value AWS_REGION)
cluster=$(environment_value PERF_ECS_CLUSTER)
service=$(environment_value PERF_ECS_SERVICE)
base_url=$(environment_value PERF_BASE_URL)
service_status=$(aws ecs describe-services --region "$region" --cluster "$cluster" --services "$service" \
  --query 'services[0].[desiredCount,runningCount,pendingCount,deployments[?status==`PRIMARY`].rolloutState | [0],taskDefinition]' --output text)
read -r desired running pending rollout task_definition <<< "$service_status"
[[ "$desired" =~ ^[1-9][0-9]*$ && "$running" == "$desired" && "$pending" == 0 && "$rollout" == COMPLETED ]] \
  || fail 'Performance ECS service is not fully deployed; complete Backend deployment before running.'
app_image=$(aws ecs describe-task-definition --region "$region" --task-definition "$task_definition" \
  --query "taskDefinition.containerDefinitions[?name=='app'].image | [0]" --output text)
app_revision=${app_image##*:}
[[ "$app_revision" =~ ^[0-9a-f]{40}$ ]] || fail 'Active app container does not have an immutable Git SHA tag.'
curl --fail --silent --show-error --connect-timeout 5 --max-time 10 "$base_url/health" >/dev/null
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$base_url/api/v1/test-suites?page=1&size=1" >/dev/null

install -d -m 0755 "$runner_root/results"
execution_dir=$(mktemp -d "$runner_root/results/execution-XXXXXXXX")
sed '/^APP_REVISION=/d' "$runner_root/environment" > "$execution_dir/environment"
printf 'APP_REVISION=%s\n' "$app_revision" >> "$execution_dir/environment"
printf '%s\n' "$task_definition" > "$execution_dir/task-definition"
printf '%s\n' "$image_reference" > "$execution_dir/runner-image"
printf 'Execution artifacts: %s\n' "$execution_dir"
# The image owns active-TestRun, empty queue/DLQ and capacity preflight, and must
# complete those checks before seeding or load. Keep its exit code and raw logs.
docker run --rm --env-file "$execution_dir/environment" \
  -v "$execution_dir:/results" --entrypoint /workspace/bin/run-performance \
  "$image_reference" "$@" --result-dir /results/run 2>&1 | tee "$execution_dir/runner.log"
