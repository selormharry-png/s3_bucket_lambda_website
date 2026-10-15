"""Review API behind a Lambda Function URL.

POST  -> validate and store a review (approved=false until you approve it)
GET   -> return approved reviews only (never includes email addresses)

CORS is handled by the Function URL configuration (see main.tf), so this code
deliberately does not add CORS headers.
"""
import base64
import json
import os
import re
import time
import uuid
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=lambda o: int(o) if isinstance(o, Decimal) else str(o)),
    }


def _list_approved():
    items, kwargs = [], {"FilterExpression": Attr("approved").eq(True)}
    while True:
        page = TABLE.scan(**kwargs)
        items.extend(page.get("Items", []))
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    items.sort(key=lambda r: r.get("created_at", 0), reverse=True)
    return [
        {"name": r.get("name", ""), "rating": int(r.get("rating", 5)), "message": r.get("message", "")}
        for r in items
    ]


def _create(payload):
    # Honeypot: real users never fill the hidden "website" field. Pretend success.
    if str(payload.get("website", "")).strip():
        return _resp(200, {"ok": True})

    name = str(payload.get("name", "")).strip()
    email = str(payload.get("email", "")).strip()
    message = str(payload.get("message", "")).strip()
    try:
        rating = int(payload.get("rating", 5))
    except (TypeError, ValueError):
        return _resp(400, {"error": "Rating must be a number from 1 to 5."})

    if not name or len(name) > 80:
        return _resp(400, {"error": "Please enter your name (max 80 characters)."})
    if not EMAIL_RE.match(email) or len(email) > 254:
        return _resp(400, {"error": "Please enter a valid email address."})
    if not message or len(message) > 1000:
        return _resp(400, {"error": "Please enter a review (max 1000 characters)."})
    if rating < 1 or rating > 5:
        return _resp(400, {"error": "Rating must be between 1 and 5."})

    TABLE.put_item(
        Item={
            "id": str(uuid.uuid4()),
            "name": name,
            "email": email,
            "rating": rating,
            "message": message,
            "approved": False,
            "created_at": int(time.time()),
        }
    )
    return _resp(200, {"ok": True})


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    try:
        if method == "GET":
            return _resp(200, _list_approved())
        if method == "POST":
            body = event.get("body") or "{}"
            # Function URLs base64-encode bodies whose content type isn't text/JSON.
            try:
                if event.get("isBase64Encoded"):
                    body = base64.b64decode(body).decode("utf-8")
                payload = json.loads(body)
            except (ValueError, UnicodeDecodeError):
                return _resp(400, {"error": "Invalid JSON."})
            if not isinstance(payload, dict):
                return _resp(400, {"error": "Invalid JSON."})
            return _create(payload)
        return _resp(405, {"error": "Method not allowed."})
    except Exception as exc:  # noqa: BLE001 - log and return a generic error
        print(f"ERROR: {exc!r}")
        return _resp(500, {"error": "Something went wrong. Please try again later."})
