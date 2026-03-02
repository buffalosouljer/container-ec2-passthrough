import boto3
import os
import time
import json
from datetime import datetime

BUCKET = os.environ["S3_BUCKET"]
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")


def main():
    s3 = boto3.client("s3", region_name=REGION)
    iteration = 0

    while True:
        iteration += 1
        timestamp = datetime.utcnow().isoformat()
        key = f"test-object-{iteration}.json"
        body = json.dumps({"iteration": iteration, "timestamp": timestamp})

        try:
            # Put object
            s3.put_object(Bucket=BUCKET, Key=key, Body=body)
            print(f"[{timestamp}] PUT s3://{BUCKET}/{key} - SUCCESS")

            # Get object
            response = s3.get_object(Bucket=BUCKET, Key=key)
            data = response["Body"].read().decode("utf-8")
            print(f"[{timestamp}] GET s3://{BUCKET}/{key} - SUCCESS: {data}")

        except Exception as e:
            print(f"[{timestamp}] ERROR: {e}")

        time.sleep(30)


if __name__ == "__main__":
    print("Container A (S3 workload) starting...")
    main()
