"""
Scans the processing DynamoDB table for failed or stale records and
re-triggers each one by copying the S3 object over itself with updated
metadata. This fires a fresh Object Created event through the pipeline.

Usage:
    uv run tools/reprocess.py --table <table-name> --region eu-west-1

Stale PROCESSING records are those older than STALE_THRESHOLD_MINUTES —
a task should complete in well under a minute, so anything older indicates
a crash before the status was updated.
"""

import argparse
import sys
from datetime import datetime, timedelta, timezone

import boto3

STALE_THRESHOLD_MINUTES = 10


def scan_failures(table, cutoff: datetime) -> list[dict]:
    response = table.scan()
    items = response["Items"]

    failures = []
    for item in items:
        if item["status"] == "FAILED":
            failures.append((item, f"FAILED — {item.get('error', 'no error recorded')}"))
        elif item["status"] == "PROCESSING":
            started = datetime.fromisoformat(item["started_at"])
            if started < cutoff:
                failures.append((item, f"PROCESSING stale since {item['started_at']}"))

    return failures


def touch(s3, bucket: str, key: str) -> None:
    s3.copy_object(
        Bucket=bucket,
        Key=key,
        CopySource={"Bucket": bucket, "Key": key},
        Metadata={"reprocessed": datetime.now(timezone.utc).isoformat()},
        MetadataDirective="REPLACE",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--table", required=True, help="DynamoDB table name")
    parser.add_argument("--region", default="eu-west-1")
    args = parser.parse_args()

    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    s3 = boto3.client("s3", region_name=args.region)
    table = dynamodb.Table(args.table)

    cutoff = datetime.now(timezone.utc) - timedelta(minutes=STALE_THRESHOLD_MINUTES)
    failures = scan_failures(table, cutoff)

    if not failures:
        print("No failed or stale records found.")
        sys.exit(0)

    print(f"Found {len(failures)} record(s) to reprocess:\n")
    for item, reason in failures:
        print(f"  s3://{item['bucket']}/{item['key']}")
        print(f"  └─ {reason}")

    print(f"\nReprocessing {len(failures)} object(s)...")
    for item, _ in failures:
        bucket = item["bucket"]
        key = item["key"]
        print(f"  Touching s3://{bucket}/{key}")
        touch(s3, bucket, key)

    print("\nDone — events are in flight, check logs in ~30s.")


if __name__ == "__main__":
    main()
