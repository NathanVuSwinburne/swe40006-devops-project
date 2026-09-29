#!/usr/bin/env bash
# Level 4: the pipeline's "deploy to production" step.
# GitHub Actions runs this AFTER the build and all tests (unit, integration, staging, E2E) pass.
#
# It does NOT use SSH. It asks AWS Systems Manager (SSM) to run deploy.sh on the
# production server, waits for it to finish, prints the server's output into the
# GitHub Actions log, and fails the pipeline if the deploy or the health check fails.
#
# Needs: AWS credentials (from the GitHub OIDC role), and these env vars:
#   PROD_INSTANCE_ID  e.g. i-0abc123...        (GitHub secret)
#   PROD_URL          e.g. http://3.104.x.x    (GitHub variable, optional)
#   DEPLOY_BRANCH     defaults to main
set -euo pipefail

INSTANCE_ID="${PROD_INSTANCE_ID:?PROD_INSTANCE_ID is not set}"
REGION="${AWS_REGION:-ap-southeast-2}"
BRANCH="${DEPLOY_BRANCH:-main}"
PUBLIC_URL="${PROD_URL:-}"
REMOTE_CMD="sudo -u ubuntu -H env DEPLOY_BRANCH=$BRANCH bash /opt/swe40006/app/deploy/production/deploy.sh"

echo "Deploying branch '$BRANCH' (commit ${GITHUB_SHA:-local}) to $INSTANCE_ID via SSM"
COMMAND_ID=$(aws ssm send-command \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "GitHub Actions deploy ${GITHUB_SHA:0:7}" \
  --parameters "$(jq -n --arg c "$REMOTE_CMD" '{commands: [$c], executionTimeout: ["900"]}')" \
  --query "Command.CommandId" --output text)
echo "SSM command id: $COMMAND_ID"

STATUS="Pending"
for _ in $(seq 1 180); do            # wait up to 15 minutes
  sleep 5
  STATUS=$(aws ssm get-command-invocation --region "$REGION" \
    --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || echo "Pending")
  case "$STATUS" in
    Pending|InProgress|Delayed) printf '.';;
    *) break;;
  esac
done
echo

echo "----- output from the production server -----"
aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --query StandardOutputContent --output text
aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --query StandardErrorContent --output text >&2 || true
echo "---------------------------------------------"

if [ "$STATUS" != "Success" ]; then
  echo "Production deploy FAILED (SSM status: $STATUS)"
  exit 1
fi

if [ -n "$PUBLIC_URL" ]; then
  echo "Checking the public URL: $PUBLIC_URL/health"
  curl -fsS --retry 5 --retry-delay 3 --retry-all-errors "$PUBLIC_URL/health"
  echo
fi
echo "Production deploy SUCCESS"
