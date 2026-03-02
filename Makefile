SSH_KEY     := ~/.ssh/container-roles-demo.pem
INSTANCE_IP := $(shell cd infra && terraform output -raw instance_public_ip 2>/dev/null)
SSH_USER    := fedora
APPUSER     := appuser
SSH_CMD     := ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no $(SSH_USER)@$(INSTANCE_IP)

.PHONY: phase1 phase2 status logs ssh keys help

help: ## Show available targets
	@echo "Usage: make <target>"
	@echo ""
	@echo "Demo lifecycle:"
	@echo "  phase1   Revert to Phase 1 (static access keys)"
	@echo "  phase2   Migrate to Phase 2 (IMDS role assumption)"
	@echo ""
	@echo "Inspection:"
	@echo "  status   Show running containers"
	@echo "  logs     Show recent logs from all containers"
	@echo "  keys     Show env vars in containers (exposes creds in Phase 1)"
	@echo "  ssh      Open an interactive SSH session"

phase1: ## Revert to Phase 1 — static access keys baked into containers
	@echo "=== Switching to Phase 1 (Legacy Static Access Keys) ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c '/home/$(APPUSER)/scripts/deploy-legacy.sh'"

phase2: ## Migrate to Phase 2 — IMDS role assumption, no static keys
	@echo "=== Switching to Phase 2 (IMDS Role Assumption) ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c '/home/$(APPUSER)/scripts/deploy-roles.sh'"

status: ## Show container status
	$(SSH_CMD) "sudo su - $(APPUSER) -c 'podman ps -a'"

logs: ## Show recent logs from all 3 containers
	@echo "=== Container A (S3) ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c 'podman logs --tail 5 container-a 2>&1'" || true
	@echo ""
	@echo "=== Container B (DynamoDB) ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c 'podman logs --tail 5 container-b 2>&1'" || true
	@echo ""
	@echo "=== Container C (KMS) ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c 'podman logs --tail 5 container-c 2>&1'" || true

keys: ## Show credential env vars in each container
	@echo "=== Container A ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c \"podman inspect container-a --format='{{range .Config.Env}}{{println .}}{{end}}'\"" | grep -E 'AWS_|S3_|DYNAMO|KMS' || true
	@echo ""
	@echo "=== Container B ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c \"podman inspect container-b --format='{{range .Config.Env}}{{println .}}{{end}}'\"" | grep -E 'AWS_|S3_|DYNAMO|KMS' || true
	@echo ""
	@echo "=== Container C ==="
	$(SSH_CMD) "sudo su - $(APPUSER) -c \"podman inspect container-c --format='{{range .Config.Env}}{{println .}}{{end}}'\"" | grep -E 'AWS_|S3_|DYNAMO|KMS' || true

ssh: ## Open interactive SSH session to the instance
	$(SSH_CMD)
