import boto3
import os
import time
import uuid
from datetime import datetime

TABLE = os.environ["DYNAMODB_TABLE"]
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")


def main():
    dynamodb = boto3.client("dynamodb", region_name=REGION)
    iteration = 0

    while True:
        iteration += 1
        timestamp = datetime.utcnow().isoformat()
        item_id = str(uuid.uuid4())[:8]

        try:
            # PutItem
            dynamodb.put_item(
                TableName=TABLE,
                Item={
                    "pk": {"S": f"test-{item_id}"},
                    "sk": {"S": timestamp},
                    "iteration": {"N": str(iteration)},
                    "message": {"S": f"Hello from container B, iteration {iteration}"},
                },
            )
            print(f"[{timestamp}] PutItem pk=test-{item_id} - SUCCESS")

            # GetItem
            response = dynamodb.get_item(
                TableName=TABLE,
                Key={
                    "pk": {"S": f"test-{item_id}"},
                    "sk": {"S": timestamp},
                },
            )
            item = response.get("Item", {})
            print(
                f"[{timestamp}] GetItem pk=test-{item_id} - SUCCESS: "
                f"{item.get('message', {}).get('S', 'N/A')}"
            )

        except Exception as e:
            print(f"[{timestamp}] ERROR: {e}")

        time.sleep(30)


if __name__ == "__main__":
    print("Container B (DynamoDB workload) starting...")
    main()
