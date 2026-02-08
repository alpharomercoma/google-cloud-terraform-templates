"""Cloud Function to stop idle Compute Engine instances.

Triggered by Pub/Sub messages from Cloud Monitoring alert policies.
When a CPU idle alert fires, this function stops the target instance
using details from environment variables.

Note: The Cloud Monitoring alert payload provides a numeric instance_id
in resource.labels, but the Compute Engine API requires the instance NAME.
To avoid unreliable name resolution, the target instance name and zone are
passed via environment variables set at deploy time.
"""

import base64
import json
import logging
import os

import functions_framework
from google.cloud import compute_v1

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@functions_framework.cloud_event
def stop_idle_instance(cloud_event):
    """Stop a Compute Engine instance when triggered by a monitoring alert.

    Args:
        cloud_event: CloudEvent containing the Pub/Sub message with
                     Cloud Monitoring alert payload.
    """
    # Read target instance details from environment variables
    project_id = os.environ.get("TARGET_PROJECT_ID")
    zone = os.environ.get("TARGET_ZONE")
    instance_name = os.environ.get("TARGET_INSTANCE_NAME")

    if not all([project_id, zone, instance_name]):
        logger.error(
            "Missing environment variables. "
            "TARGET_PROJECT_ID=%s, TARGET_ZONE=%s, TARGET_INSTANCE_NAME=%s",
            project_id, zone, instance_name,
        )
        return

    # Decode the Pub/Sub message data
    pubsub_data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    alert_payload = json.loads(pubsub_data)

    logger.info("Received alert: %s", json.dumps(alert_payload, indent=2))

    # Extract incident details
    incident = alert_payload.get("incident", {})
    state = incident.get("state", "")

    # Only act on OPEN incidents (not resolved ones)
    if state != "open":
        logger.info("Incident state is '%s', not 'open'. Skipping.", state)
        return

    logger.info(
        "Stopping instance: project=%s, zone=%s, instance=%s",
        project_id, zone, instance_name,
    )

    # Stop the instance
    client = compute_v1.InstancesClient()

    try:
        operation = client.stop(
            project=project_id,
            zone=zone,
            instance=instance_name,
        )
        operation.result(timeout=300)
        logger.info("Successfully stopped instance %s in %s", instance_name, zone)
    except Exception as e:
        logger.error("Failed to stop instance %s: %s", instance_name, e)
        raise
