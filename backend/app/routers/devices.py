"""
Push device registration — the cloud half of the two-layer alarm needs to know
where to send a notification.

The app posts its FCM/APNs token; we create an SNS platform endpoint and
subscribe it to the notifications topic with a filter policy on the user's id,
so a publish tagged with user_id reaches only that user's devices.
"""

import json
import logging

import boto3
from email_validator import EmailNotValidError, validate_email
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.auth import get_current_user_id
from app.config import settings

router = APIRouter()
logger = logging.getLogger(__name__)


class DeviceRegistration(BaseModel):
    token: str
    platform: str = "fcm"  # fcm | apns


def filter_policy(user_id: str) -> str:
    return json.dumps({"user_id": [user_id]})


@router.post("")
async def register_device(
    body: DeviceRegistration,
    user_id: str = Depends(get_current_user_id),
):
    if not (settings.sns_platform_app_arn and settings.notification_topic_arn):
        raise HTTPException(status_code=503, detail="Push notifications are not configured")
    sns = boto3.client("sns", region_name=settings.aws_region)
    try:
        endpoint = sns.create_platform_endpoint(
            PlatformApplicationArn=settings.sns_platform_app_arn,
            Token=body.token,
            CustomUserData=user_id,
        )["EndpointArn"]
        sns.subscribe(
            TopicArn=settings.notification_topic_arn,
            Protocol="application",
            Endpoint=endpoint,
            Attributes={"FilterPolicy": filter_policy(user_id)},
            ReturnSubscriptionArn=True,
        )
    except Exception:
        logger.exception("Device registration failed")
        raise HTTPException(status_code=502, detail="Could not register device")
    return {"registered": True}


class EmailRegistration(BaseModel):
    email: str


@router.post("/email")
async def register_email(
    body: EmailRegistration,
    user_id: str = Depends(get_current_user_id),
):
    """Email me my reminders: a cloud alarm channel that needs no mobile push setup.

    SNS emails a confirmation link first (nothing is sent until the address is
    confirmed), and the subscription is filtered to this user's reminders only."""
    if not settings.notification_topic_arn:
        raise HTTPException(status_code=503, detail="Reminder emails are not configured")
    try:
        email = validate_email(body.email.strip(), check_deliverability=False).normalized
    except EmailNotValidError:
        raise HTTPException(status_code=422, detail="Enter a valid email address")
    try:
        boto3.client("sns", region_name=settings.aws_region).subscribe(
            TopicArn=settings.notification_topic_arn,
            Protocol="email",
            Endpoint=email,
            Attributes={"FilterPolicy": filter_policy(user_id)},
            ReturnSubscriptionArn=True,
        )
    except Exception:
        logger.exception("Email subscription failed")
        raise HTTPException(status_code=502, detail="Could not set up reminder emails")
    return {"status": "pending_confirmation", "email": email,
            "detail": "Check your inbox and click the confirmation link to start receiving reminders."}
