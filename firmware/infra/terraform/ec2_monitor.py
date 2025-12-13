import os
import boto3
from datetime import datetime, timezone
from typing import Optional, Tuple

region = os.environ.get('AWS_REGION', 'us-east-2')
ec2 = boto3.client('ec2', region_name=region)
sns = boto3.client('sns', region_name=region)

INSTANCE_NAME = os.environ['INSTANCE_NAME']
ALERT_THRESHOLD_HOURS = int(os.environ['ALERT_THRESHOLD_HOURS'])
ALERT_INTERVAL_HOURS = int(os.environ['ALERT_INTERVAL_HOURS'])
ARCHIVE_AFTER_HOURS = int(os.environ.get('ARCHIVE_AFTER_HOURS', '24'))
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
DATA_VOLUME_NAME = 'yocto-builder-data'
SNAPSHOT_NAME = 'yocto-builder-data-snapshot'


def get_instance(state_filter: list[str] = None) -> Optional[dict]:
    """Get instance by name tag."""
    filters = [{'Name': 'tag:Name', 'Values': [INSTANCE_NAME]}]
    if state_filter:
        filters.append({'Name': 'instance-state-name', 'Values': state_filter})

    response = ec2.describe_instances(Filters=filters)
    reservations = response.get('Reservations', [])
    if not reservations or not reservations[0].get('Instances'):
        return None
    return reservations[0]['Instances'][0]


def get_instance_uptime_hours(instance: dict) -> int:
    """Get instance uptime in hours."""
    launch_time = instance['LaunchTime']
    now = datetime.now(timezone.utc)
    return int((now - launch_time).total_seconds() / 3600)


def get_stopped_duration_hours(instance: dict) -> Optional[int]:
    """Get hours since instance was stopped (from state transition time)."""
    state_reason = instance.get('StateTransitionReason', '')
    if not state_reason or 'User initiated' not in state_reason:
        return None
    try:
        # Format: "User initiated (2024-01-15 10:30:45 GMT)"
        time_str = state_reason.split('(')[1].split(')')[0].replace(' GMT', '')
        stopped_time = datetime.strptime(time_str, '%Y-%m-%d %H:%M:%S')
        stopped_time = stopped_time.replace(tzinfo=timezone.utc)
        return int((datetime.now(timezone.utc) - stopped_time).total_seconds() / 3600)
    except (IndexError, ValueError):
        return None


def get_data_volume() -> Optional[str]:
    """Get data volume ID by name tag."""
    response = ec2.describe_volumes(
        Filters=[
            {'Name': 'tag:Name', 'Values': [DATA_VOLUME_NAME]},
            {'Name': 'status', 'Values': ['available', 'in-use']}
        ]
    )
    volumes = response.get('Volumes', [])
    return volumes[0]['VolumeId'] if volumes else None


def archive_data_volume(volume_id: str) -> Tuple[bool, str]:
    """Snapshot and delete the data volume."""
    try:
        # Create snapshot
        snapshot = ec2.create_snapshot(
            VolumeId=volume_id,
            Description=f'Auto-archive {datetime.now(timezone.utc).strftime("%Y-%m-%d")}',
            TagSpecifications=[{
                'ResourceType': 'snapshot',
                'Tags': [{'Key': 'Name', 'Value': SNAPSHOT_NAME}]
            }]
        )
        snap_id = snapshot['SnapshotId']

        # Wait for snapshot (with timeout)
        waiter = ec2.get_waiter('snapshot_completed')
        waiter.wait(SnapshotIds=[snap_id], WaiterConfig={'Delay': 30, 'MaxAttempts': 60})

        # Detach if attached
        vol_info = ec2.describe_volumes(VolumeIds=[volume_id])['Volumes'][0]
        if vol_info['Attachments']:
            ec2.detach_volume(VolumeId=volume_id, Force=True)
            ec2.get_waiter('volume_available').wait(VolumeIds=[volume_id])

        # Delete volume
        ec2.delete_volume(VolumeId=volume_id)

        return True, f'Archived volume {volume_id} to snapshot {snap_id}'
    except Exception as e:
        return False, f'Archive failed: {str(e)}'


def should_alert(uptime_hours: int) -> bool:
    """Determine if we should send an alert."""
    if uptime_hours < ALERT_THRESHOLD_HOURS:
        return False
    hours_over = uptime_hours - ALERT_THRESHOLD_HOURS
    return hours_over % ALERT_INTERVAL_HOURS == 0


def send_alert(subject: str, message: str):
    """Send SNS notification."""
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)


def lambda_handler(event, context):
    """Check for running alerts and auto-archive idle data volumes."""
    results = []

    # Check running instance for uptime alerts
    running = get_instance(['running'])
    if running:
        uptime = get_instance_uptime_hours(running)
        if should_alert(uptime):
            send_alert(
                f"EC2 Instance Running Alert",
                f"EC2 instance {running['InstanceId']} ({INSTANCE_NAME}) has been running for {uptime} hours."
            )
            results.append(f'Alert sent: running for {uptime}h')
        else:
            results.append(f'Running for {uptime}h, no alert needed')

    # Check stopped instance for auto-archive
    stopped = get_instance(['stopped'])
    if stopped:
        stopped_hours = get_stopped_duration_hours(stopped)
        volume_id = get_data_volume()

        if stopped_hours and stopped_hours >= ARCHIVE_AFTER_HOURS and volume_id:
            success, msg = archive_data_volume(volume_id)
            results.append(msg)
            if success:
                send_alert(
                    "Data Volume Auto-Archived",
                    f"Instance stopped for {stopped_hours}h. Data volume archived to save costs. "
                    f"Will auto-restore on next start."
                )
        elif volume_id:
            results.append(f'Stopped {stopped_hours}h, archive after {ARCHIVE_AFTER_HOURS}h')
        else:
            results.append('Stopped, no data volume to archive')

    if not running and not stopped:
        results.append('Instance not found')

    return {'statusCode': 200, 'body': '; '.join(results)}

