"""
Pre-provisioning hook for AWS IoT Fleet Provisioning.
Cleans up existing thing and certificates if device is being re-provisioned.
"""

import json
import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot = boto3.client('iot')


def handler(event, context):
    """
    Pre-provisioning hook entry point.
    Called by AWS IoT before RegisterThing to allow cleanup of old resources.
    """
    logger.info(f"Pre-provisioning hook called: {json.dumps(event)}")

    parameters = event.get('parameters', {})
    thing_name = parameters.get('ThingName')
    serial_number = parameters.get('SerialNumber')

    if not thing_name:
        logger.error("ThingName not provided")
        return {'allowProvisioning': False}

    # Check if thing already exists
    try:
        iot.describe_thing(thingName=thing_name)
        logger.info(f"Thing {thing_name} exists, cleaning up for re-provision")
        cleanup_thing(thing_name)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.info(f"Thing {thing_name} does not exist, proceeding with provisioning")
        else:
            logger.error(f"Error checking thing: {e}")
            return {'allowProvisioning': False}

    return {'allowProvisioning': True}


def cleanup_thing(thing_name):
    """Remove thing and its attached certificates."""
    # Get attached principals (certificates)
    try:
        principals = iot.list_thing_principals(thingName=thing_name)['principals']
    except ClientError as e:
        logger.warning(f"Could not list principals for {thing_name}: {e}")
        principals = []

    # Detach and delete each certificate
    for principal in principals:
        cert_id = principal.split('/')[-1]
        logger.info(f"Cleaning up certificate {cert_id}")

        try:
            # Detach from thing
            iot.detach_thing_principal(thingName=thing_name, principal=principal)
        except ClientError as e:
            logger.warning(f"Could not detach principal: {e}")

        try:
            # Detach policies from certificate
            policies = iot.list_attached_policies(target=principal)['policies']
            for policy in policies:
                iot.detach_policy(policyName=policy['policyName'], target=principal)
        except ClientError as e:
            logger.warning(f"Could not detach policies: {e}")

        try:
            # Deactivate and delete certificate
            iot.update_certificate(certificateId=cert_id, newStatus='INACTIVE')
            iot.delete_certificate(certificateId=cert_id)
            logger.info(f"Deleted certificate {cert_id}")
        except ClientError as e:
            logger.warning(f"Could not delete certificate: {e}")

    # Delete the thing
    try:
        iot.delete_thing(thingName=thing_name)
        logger.info(f"Deleted thing {thing_name}")
    except ClientError as e:
        logger.warning(f"Could not delete thing: {e}")

