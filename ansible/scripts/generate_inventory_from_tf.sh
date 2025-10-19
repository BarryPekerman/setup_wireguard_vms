#!/usr/bin/env bash
set -euo pipefail

# Generate Ansible inventory from Terraform outputs
# Requirements: terraform, jq

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INV_DIR="$ANSIBLE_DIR/inventory"

mkdir -p "$INV_DIR"

echo "[INFO] Reading Terraform outputs..." >&2
OUT_JSON=$(terraform -chdir="$TF_DIR" output -json)

BASTION_IP=$(echo "$OUT_JSON" | jq -r '.bastion_public_ip.value // empty')
PRIVATE_IP=$(echo "$OUT_JSON" | jq -r '.private_instance_ip.value // empty')

if [[ -z "$BASTION_IP" || -z "$PRIVATE_IP" ]]; then
  echo "[ERROR] Missing outputs. Ensure 'terraform apply' completed successfully." >&2
  exit 1
fi

SSH_KEY_PATH=$(echo "$OUT_JSON" | jq -r '.bastion_ssh_command.value | capture("-i (?<k>[^ ]+)").k // empty')
if [[ -z "$SSH_KEY_PATH" ]]; then
  SSH_KEY_PATH="$TF_DIR/keys/wireguard_key"
fi
# If SSH_KEY_PATH is relative, make it absolute relative to terraform dir
if [[ "$SSH_KEY_PATH" != /* ]]; then
  SSH_KEY_PATH="$TF_DIR/${SSH_KEY_PATH}"
fi

{
  echo "[bastion_group]"
  echo "bastion ansible_host=$BASTION_IP ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY_PATH ansible_ssh_common_args='-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
  echo
  echo "[private_group]"
  echo "private ansible_host=$PRIVATE_IP ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY_PATH ansible_ssh_common_args='-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY_PATH -W %h:%p ubuntu@$BASTION_IP\"'"
  echo
  echo "[wireguard:children]"
  echo "bastion_group"
  echo "private_group"
} > "$INV_DIR/infrastructure.ini"

echo "[INFO] Wrote inventory: $INV_DIR/infrastructure.ini" >&2

