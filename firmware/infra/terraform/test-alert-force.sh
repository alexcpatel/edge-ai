#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Force test the alert by temporarily lowering the threshold to 0 hours
# This will trigger an alert if the instance is running

FUNCTION_NAME="yocto-instance-uptime-alert"
REGION="us-east-2"

echo "Testing alert by temporarily setting threshold to 0 hours..."
echo ""

# Get current environment variables
current_config=$(aws lambda get-function-configuration \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --query 'Environment.Variables' \
    --output json)

INSTANCE_NAME=$(echo "$current_config" | python3 -c "import sys, json; print(json.load(sys.stdin)['INSTANCE_NAME'])")
ALERT_INTERVAL_HOURS=$(echo "$current_config" | python3 -c "import sys, json; print(json.load(sys.stdin)['ALERT_INTERVAL_HOURS'])")
SNS_TOPIC_ARN=$(echo "$current_config" | python3 -c "import sys, json; print(json.load(sys.stdin)['SNS_TOPIC_ARN'])")

# Update threshold to 0 to force an alert
aws lambda update-function-configuration \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --environment "Variables={INSTANCE_NAME=$INSTANCE_NAME,ALERT_THRESHOLD_HOURS=0,ALERT_INTERVAL_HOURS=$ALERT_INTERVAL_HOURS,SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    >/dev/null 2>&1

echo "✓ Updated threshold to 0 hours"
echo "Waiting for Lambda to update..."
sleep 3

# Invoke the function
echo "Invoking Lambda..."
aws lambda invoke \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --payload '{}' \
    /tmp/lambda-response.json >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "Response:"
    cat /tmp/lambda-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/lambda-response.json
    echo ""

    if grep -q "Alert sent" /tmp/lambda-response.json 2>/dev/null; then
        echo "✓ Alert was sent! Check your email: $(cd "$(dirname "$0")" && terraform output -raw notification_email 2>/dev/null || echo 'configured email')"
    fi
else
    echo "✗ Failed to invoke Lambda"
    exit 1
fi

# Restore original threshold (5 hours)
echo ""
echo "Restoring original threshold (5 hours)..."
aws lambda update-function-configuration \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --environment "Variables={INSTANCE_NAME=$INSTANCE_NAME,ALERT_THRESHOLD_HOURS=5,ALERT_INTERVAL_HOURS=$ALERT_INTERVAL_HOURS,SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    >/dev/null 2>&1

echo "✓ Restored original configuration"

