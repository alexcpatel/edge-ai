#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Test the Lambda alerting function
# This will invoke the Lambda and show the response

FUNCTION_NAME="yocto-instance-uptime-alert"
REGION="us-east-2"

echo "Testing Lambda function: $FUNCTION_NAME"
echo ""

# Invoke the Lambda function
response=$(aws lambda invoke \
    --region "$REGION" \
    --function-name "$FUNCTION_NAME" \
    --payload '{}' \
    /tmp/lambda-response.json 2>&1)

if [ $? -eq 0 ]; then
    echo "✓ Lambda invoked successfully"
    echo ""
    echo "Response:"
    cat /tmp/lambda-response.json | python3 -m json.tool 2>/dev/null || cat /tmp/lambda-response.json
    echo ""

    # Check if alert was sent
    if grep -q "Alert sent" /tmp/lambda-response.json 2>/dev/null; then
        echo "✓ Alert was sent! Check your email: $(terraform output -raw notification_email 2>/dev/null || echo 'configured email')"
    elif grep -q "No alert needed" /tmp/lambda-response.json 2>/dev/null; then
        echo "ℹ No alert sent (instance uptime below threshold or not at alert interval)"
    fi

    # Show recent CloudWatch logs
    echo ""
    echo "Recent Lambda logs:"
    aws logs tail "/aws/lambda/$FUNCTION_NAME" \
        --region "$REGION" \
        --since 5m \
        --format short 2>/dev/null || echo "  (No recent logs)"
else
    echo "✗ Failed to invoke Lambda"
    echo "$response"
    exit 1
fi

