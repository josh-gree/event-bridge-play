import hashlib
import os
import random
import sys
from datetime import datetime, timezone

import boto3

TABLE = os.environ["DYNAMODB_TABLE"]
FAILURE_PROBABILITY = float(os.environ.get("FAILURE_PROBABILITY", "0.0"))


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> None:
    bucket = os.environ.get("S3_BUCKET")
    key = os.environ.get("S3_KEY")

    if not bucket or not key:
        print("S3_BUCKET and S3_KEY must be set.", file=sys.stderr)
        sys.exit(1)

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(TABLE)

    # Write PROCESSING immediately. If the task crashes before updating this
    # record it will remain as PROCESSING — the reprocess script treats any
    # PROCESSING record older than 10 minutes as stale and re-triggers it.
    table.put_item(Item={
        "bucket": bucket,
        "key": key,
        "status": "PROCESSING",
        "started_at": now(),
    })
    print(f"Marked s3://{bucket}/{key} as PROCESSING")

    try:
        if random.random() < FAILURE_PROBABILITY:
            raise RuntimeError("Simulated random failure")

        print(f"Downloading s3://{bucket}/{key}")
        s3 = boto3.client("s3")
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        sha256 = hashlib.sha256(body).hexdigest()
        print(f"SHA256: {sha256}")

        table.update_item(
            Key={"bucket": bucket, "key": key},
            UpdateExpression="SET #s = :status, completed_at = :completed_at, sha256 = :sha256",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":status": "SUCCESS",
                ":completed_at": now(),
                ":sha256": sha256,
            },
        )
        print("Marked as SUCCESS")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        table.update_item(
            Key={"bucket": bucket, "key": key},
            UpdateExpression="SET #s = :status, completed_at = :completed_at, #e = :error",
            ExpressionAttributeNames={"#s": "status", "#e": "error"},
            ExpressionAttributeValues={
                ":status": "FAILED",
                ":completed_at": now(),
                ":error": str(e),
            },
        )
        print("Marked as FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
