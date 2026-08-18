#!/usr/bin/env bash
# Run this ONCE after GitLab CE is fully up (http://localhost:8929 loads).
#
# How to get RUNNER_TOKEN:
#   GitLab → your project → Settings → CI/CD → Runners → "New project runner"
#   Tick "Run untagged jobs" → Create runner → copy the token shown.
#
# Usage:
#   chmod +x register-runner.sh
#   RUNNER_TOKEN=glrt-xxxx ./register-runner.sh

set -euo pipefail

: "${RUNNER_TOKEN:?Set RUNNER_TOKEN before running this script}"
GITLAB_PORT="${GITLAB_PORT:-8929}"

docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "http://gitlab:${GITLAB_PORT}" \
  --token "${RUNNER_TOKEN}" \
  --executor "docker" \
  --docker-image "docker:26" \
  --docker-privileged \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --description "compose-runner"

echo "Runner registered. Trigger a pipeline with: git push gitlab main"
