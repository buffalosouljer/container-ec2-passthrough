import boto3
import os
import time
from datetime import datetime

KMS_KEY_ID = os.environ["KMS_KEY_ID"]
REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")


def main():
    kms = boto3.client("kms", region_name=REGION)
    iteration = 0

    while True:
        iteration += 1
        timestamp = datetime.utcnow().isoformat()
        plaintext = f"Secret message #{iteration} at {timestamp}"

        try:
            # Encrypt
            encrypt_response = kms.encrypt(
                KeyId=KMS_KEY_ID, Plaintext=plaintext.encode("utf-8")
            )
            ciphertext = encrypt_response["CiphertextBlob"]
            print(
                f"[{timestamp}] Encrypt - SUCCESS "
                f"(ciphertext length: {len(ciphertext)} bytes)"
            )

            # Decrypt
            decrypt_response = kms.decrypt(CiphertextBlob=ciphertext)
            decrypted = decrypt_response["Plaintext"].decode("utf-8")
            print(f"[{timestamp}] Decrypt - SUCCESS: {decrypted}")

        except Exception as e:
            print(f"[{timestamp}] ERROR: {e}")

        time.sleep(30)


if __name__ == "__main__":
    print("Container C (KMS workload) starting...")
    main()
