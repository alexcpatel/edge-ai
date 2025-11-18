import os
import boto3
from datetime import datetime, timezone
from typing import Optional

# AWS_REGION is automatically set by Lambda runtime
region = os.environ.get('AWS_REGION', 'us-east-2')
ec2 = boto3.client('ec2', region_name=region)
sns = boto3.client('sns', region_name=region)

INSTANCE_NAME = os.environ['INSTANCE_NAME']
ALERT_THRESHOLD_HOURS = int(os.environ['ALERT_THRESHOLD_HOURS'])
ALERT_INTERVAL_HOURS = int(os.environ['ALERT_INTERVAL_HOURS'])
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']


def get_instance_id() -> Optional[str]:
    """Get instance ID by name tag."""
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': [INSTANCE_NAME]},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )

    reservations = response.get('Reservations', [])
    if not reservations:
        return None

    instances = reservations[0].get('Instances', [])
    if not instances:
        return None

    return instances[0]['InstanceId']


def get_instance_uptime_hours(instance_id: str) -> Optional[int]:
    """Get instance uptime in hours."""
    response = ec2.describe_instances(InstanceIds=[instance_id])

    instances = response.get('Reservations', [])
    if not instances:
        return None

    instance = instances[0]['Instances'][0]
    launch_time = instance['LaunchTime']

    now = datetime.now(timezone.utc)
    uptime = now - launch_time
    uptime_hours = int(uptime.total_seconds() / 3600)

    return uptime_hours


def should_alert(uptime_hours: int) -> bool:
    """Determine if we should send an alert."""
    if uptime_hours < ALERT_THRESHOLD_HOURS:
        return False

    hours_over = uptime_hours - ALERT_THRESHOLD_HOURS
    return hours_over % ALERT_INTERVAL_HOURS == 0


def send_alert(instance_id: str, uptime_hours: int):
    """Send SNS notification."""
    subject = f"EC2 Instance {instance_id} Running Alert"
    message = (
        f"EC2 instance {instance_id} ({INSTANCE_NAME}) has been running "
        f"for {uptime_hours} hours.\n\n"
        f"Please check if the instance should be stopped to avoid unnecessary costs."
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message=message
    )


def lambda_handler(event, context):
    """Lambda handler function."""
    instance_id = get_instance_id()

    if not instance_id:
        return {
            'statusCode': 200,
            'body': f'Instance {INSTANCE_NAME} not running, no alert needed'
        }

    uptime_hours = get_instance_uptime_hours(instance_id)

    if uptime_hours is None:
        return {
            'statusCode': 500,
            'body': f'Failed to get uptime for instance {instance_id}'
        }

    if should_alert(uptime_hours):
        send_alert(instance_id, uptime_hours)
        return {
            'statusCode': 200,
            'body': f'Alert sent: instance {instance_id} running for {uptime_hours} hours'
        }

    return {
        'statusCode': 200,
        'body': f'No alert needed: instance {instance_id} running for {uptime_hours} hours'
    }

