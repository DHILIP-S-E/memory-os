#!/usr/bin/env bash
# Cloud processing + cloud alarms, deployed lean: no VPC, no NAT, no containers.
#   photo/voice/document upload -> S3 -> EventBridge -> SQS (+DLQ) -> pmos-capture-processor Lambda
#   reminder fire time          -> EventBridge Scheduler -> pmos-notification-dispatcher Lambda -> SNS
# Lambdas run outside a VPC because the database (Neon) is public; that avoids ~$32/month of NAT.
# Safe to re-run: every step creates or updates. Usage: infra/deploy/deploy-cloud.sh
set -euo pipefail
cd "$(dirname "$0")"; . ./config.sh
BUCKET="personal-memory-os-captures-$ACCOUNT_ID"
TMP=$(python -c "import tempfile; print(tempfile.mkdtemp().replace(chr(92), '/'))")
ARN() { echo "arn:aws:$1:$AWS_REGION:$ACCOUNT_ID:$2"; }
ROLE() { echo "arn:aws:iam::$ACCOUNT_ID:role/$1"; }
TRUST() { cat > "$TMP/trust-$1.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"$2"},"Action":"sts:AssumeRole"}]}
EOF
}
ensure_role() {  # name service
  TRUST "$1" "$2"
  aws iam create-role --role-name "$1" --assume-role-policy-document "file://$TMP/trust-$1.json" >/dev/null 2>&1 || true
}
put_policy() {  # role name file
  aws iam put-role-policy --role-name "$1" --policy-name "$2" --policy-document "file://$3"
}

# --- 1. Package: pure-Python app + Linux wheels, no Docker needed -------------------------
PKG="$TMP/pkg"; mkdir -p "$PKG"
pip install -q --no-compile --target "$PKG" --platform manylinux2014_x86_64 --python-version 3.11 \
  --only-binary=:all: psycopg2-binary pydantic pydantic-settings tzdata email-validator
cp -r ../../backend/app ../../backend/workers "$PKG/"
find "$PKG" -name __pycache__ -prune -exec rm -rf {} +
(cd "$PKG" && python -c "
import zipfile, os, sys
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk('.'):
        for f in files:
            p = os.path.join(root, f); z.write(p, os.path.relpath(p, '.').replace(os.sep, '/'))
" "$TMP/function.zip")
echo "Package: $(du -h "$TMP/function.zip" | cut -f1)"

# --- 2. Messaging: SNS topic, SQS queue with a dead-letter queue ---------------------------
TOPIC=$(aws sns create-topic --name pmos-notifications --region "$AWS_REGION" --query TopicArn --output text)
DLQ_URL=$(aws sqs create-queue --queue-name pmos-capture-dlq --region "$AWS_REGION" \
  --attributes MessageRetentionPeriod=1209600 --query QueueUrl --output text)
DLQ_ARN=$(ARN sqs pmos-capture-dlq)
QUEUE_URL=$(aws sqs create-queue --queue-name pmos-capture-queue --region "$AWS_REGION" --query QueueUrl --output text)
QUEUE_ARN=$(ARN sqs pmos-capture-queue)
cat > "$TMP/queue-attrs.json" <<EOF
{"VisibilityTimeout":"360","MessageRetentionPeriod":"345600",
 "RedrivePolicy":"{\"deadLetterTargetArn\":\"$DLQ_ARN\",\"maxReceiveCount\":\"3\"}",
 "Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"events.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"$QUEUE_ARN\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"$(ARN events rule/pmos-capture-uploaded)\"}}}]}"}
EOF
aws sqs set-queue-attributes --queue-url "$QUEUE_URL" --region "$AWS_REGION" --attributes "file://$TMP/queue-attrs.json"

# --- 3. S3 -> EventBridge -> SQS (only capture uploads and Transcribe results) -----------------
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" \
  --notification-configuration '{"EventBridgeConfiguration":{}}'
cat > "$TMP/pattern.json" <<EOF
{"source":["aws.s3"],"detail-type":["Object Created"],
 "detail":{"bucket":{"name":["$BUCKET"]},"object":{"key":[{"prefix":"users/"},{"prefix":"processed/"}]}}}
EOF
aws events put-rule --name pmos-capture-uploaded --region "$AWS_REGION" --event-pattern "file://$TMP/pattern.json" >/dev/null
aws events put-targets --rule pmos-capture-uploaded --region "$AWS_REGION" \
  --targets "Id=queue,Arn=$QUEUE_ARN" >/dev/null

# --- 4. Roles (least privilege) ---------------------------------------------------------------
ensure_role pmos-capture-worker lambda.amazonaws.com
cat > "$TMP/worker.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"},
 {"Effect":"Allow","Action":["s3:GetObject","s3:PutObject"],"Resource":"arn:aws:s3:::$BUCKET/*"},
 {"Effect":"Allow","Action":["bedrock:InvokeModel"],"Resource":[
   "$(ARN bedrock inference-profile/apac.amazon.nova-lite-v1:0)","arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0"]},
 {"Effect":"Allow","Action":["transcribe:StartTranscriptionJob","transcribe:GetTranscriptionJob"],"Resource":"*"},
 {"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"$QUEUE_ARN"},
 {"Effect":"Allow","Action":["ssm:GetParameter"],"Resource":"$(ARN ssm parameter/pmos/*)"}]}
EOF
put_policy pmos-capture-worker access "$TMP/worker.json"

ensure_role pmos-dispatcher lambda.amazonaws.com
cat > "$TMP/dispatcher.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"},
 {"Effect":"Allow","Action":["sns:Publish"],"Resource":"$TOPIC"},
 {"Effect":"Allow","Action":["ssm:GetParameter"],"Resource":"$(ARN ssm parameter/pmos/*)"}]}
EOF
put_policy pmos-dispatcher access "$TMP/dispatcher.json"

ensure_role pmos-scheduler scheduler.amazonaws.com
sleep 10  # IAM propagation before Lambda/Scheduler use the new roles

# --- 5. Functions -------------------------------------------------------------------------------
deploy_fn() {  # name handler role timeout memory env-json
  if aws lambda get-function --function-name "$1" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws lambda update-function-code --function-name "$1" --zip-file "fileb://$TMP/function.zip" --region "$AWS_REGION" >/dev/null
    aws lambda wait function-updated --function-name "$1" --region "$AWS_REGION"
    aws lambda update-function-configuration --function-name "$1" --handler "$2" --timeout "$4" --memory-size "$5" \
      --environment "$6" --region "$AWS_REGION" >/dev/null
  else
    aws lambda create-function --function-name "$1" --runtime python3.11 --handler "$2" \
      --role "$(ROLE $3)" --zip-file "fileb://$TMP/function.zip" --timeout "$4" --memory-size "$5" \
      --environment "$6" --region "$AWS_REGION" >/dev/null
  fi
  aws lambda wait function-active --function-name "$1" --region "$AWS_REGION"
  aws logs create-log-group --log-group-name "/aws/lambda/$1" --region "$AWS_REGION" >/dev/null 2>&1 || true
  aws logs put-retention-policy --log-group-name "/aws/lambda/$1" --retention-in-days 14 --region "$AWS_REGION"
}
deploy_fn pmos-capture-processor workers.capture_processor.handler pmos-capture-worker 300 512 \
  "Variables={DATABASE_URL_PARAM=/pmos/DATABASE_URL,CAPTURE_BUCKET=$BUCKET,BEDROCK_MODEL_FAST=apac.amazon.nova-lite-v1:0}"
deploy_fn pmos-notification-dispatcher workers.notification_dispatcher.handler pmos-dispatcher 30 256 \
  "Variables={DATABASE_URL_PARAM=/pmos/DATABASE_URL,NOTIFICATION_TOPIC_ARN=$TOPIC}"
# Cost guard: at most 2 concurrent workers (the account's Lambda limit is too low for reserved concurrency).
aws lambda create-event-source-mapping --function-name pmos-capture-processor --event-source-arn "$QUEUE_ARN"   --batch-size 1 --function-response-types ReportBatchItemFailures   --scaling-config MaximumConcurrency=2 --region "$AWS_REGION" >/dev/null 2>&1 || true

# --- 6. Scheduler: group + role that may invoke only the dispatcher ----------------------------
DISPATCHER_ARN=$(ARN lambda function:pmos-notification-dispatcher)
cat > "$TMP/scheduler.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"lambda:InvokeFunction","Resource":"$DISPATCHER_ARN"}]}
EOF
put_policy pmos-scheduler invoke-dispatcher "$TMP/scheduler.json"
aws scheduler create-schedule-group --name personal-memory-os --region "$AWS_REGION" >/dev/null 2>&1 || true

# --- 7. Let the API create schedules, queue captures and subscribe emails -----------------------
cat > "$TMP/api.json" <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["scheduler:CreateSchedule","scheduler:DeleteSchedule","scheduler:GetSchedule","scheduler:UpdateSchedule"],
  "Resource":"$(ARN scheduler schedule/personal-memory-os/*)"},
 {"Effect":"Allow","Action":"iam:PassRole","Resource":"$(ROLE pmos-scheduler)"},
 {"Effect":"Allow","Action":"sqs:SendMessage","Resource":"$QUEUE_ARN"},
 {"Effect":"Allow","Action":["sns:Subscribe","sns:CreatePlatformEndpoint"],"Resource":["$TOPIC","$(ARN sns app/*)"]}]}
EOF
put_policy pmos-apprunner-instance cloud-features "$TMP/api.json"

cat <<EOF

Deployed. Set these on the App Runner service (see deploy-backend.sh):
  SCHEDULER_TARGET_ARN=$DISPATCHER_ARN
  SCHEDULER_ROLE_ARN=$(ROLE pmos-scheduler)
  SCHEDULER_GROUP=personal-memory-os
  CAPTURE_QUEUE_URL=$QUEUE_URL
  NOTIFICATION_TOPIC_ARN=$TOPIC
EOF
