"""
Uploads N test files to the S3 bucket to exercise the pipeline.

Usage:
    uv run tools/upload_test_files.py --bucket <bucket-name> --count 100 --region eu-west-1
"""

import argparse
import hashlib

import boto3


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--region", default="eu-west-1")
    args = parser.parse_args()

    s3 = boto3.client("s3", region_name=args.region)

    for i in range(args.count):
        key = f"test/file-{i:04d}.txt"
        content = f"test file {i}\n".encode()
        s3.put_object(Bucket=args.bucket, Key=key, Body=content)
        expected = hashlib.sha256(content).hexdigest()
        print(f"  [{i+1:>4}/{args.count}] uploaded {key} (expected SHA256: {expected})")

    print(f"\nDone — {args.count} files uploaded.")


if __name__ == "__main__":
    main()
