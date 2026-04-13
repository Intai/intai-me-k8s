include .env
export

install: ## Install Python + Ansible dependencies
	pip install -e .
	ansible-galaxy install -r ansible/requirements.yml
	helm plugin install --verify=false https://github.com/databus23/helm-diff || helm plugin update diff

QEMU_ACCELERATOR := $(if $(filter Darwin,$(shell uname -s)),hvf,kvm)

image: ## Build KVM base image with Packer
	cd packer && packer init . && packer build \
	  -var "vm_cpus=$(VM_CPUS)" \
	  -var "vm_memory_mb=$(VM_MEMORY_MB)" \
	  -var "disk_size=$(VM_DISK_GB)G" \
	  -var "qemu_accelerator=$(QEMU_ACCELERATOR)" \
	  .

tf-init: ## Terraform init
	cd terraform && terraform init

tf-plan: ## Terraform plan
	cd terraform && terraform plan \
	  -var "aws_region=$(AWS_REGION)" \
	  -var "project_name=$(PROJECT_NAME)" \
	  -var "environment=$(ENVIRONMENT)" \
	  -var "domain_name=$(DOMAIN_NAME)" \
	  -var "instance_type=$(INSTANCE_TYPE)" \
	  -var "vm_disk_gb=$(VM_DISK_GB)"

tf-apply: ## Terraform apply — provision AWS
	cd terraform && terraform apply -auto-approve \
	  -var "aws_region=$(AWS_REGION)" \
	  -var "project_name=$(PROJECT_NAME)" \
	  -var "environment=$(ENVIRONMENT)" \
	  -var "domain_name=$(DOMAIN_NAME)" \
	  -var "instance_type=$(INSTANCE_TYPE)" \
	  -var "vm_disk_gb=$(VM_DISK_GB)"

tf-destroy: ## Terraform destroy
	cd terraform && terraform destroy -auto-approve \
	  -var "aws_region=$(AWS_REGION)" \
	  -var "project_name=$(PROJECT_NAME)" \
	  -var "environment=$(ENVIRONMENT)" \
	  -var "domain_name=$(DOMAIN_NAME)" \
	  -var "instance_type=$(INSTANCE_TYPE)" \
	  -var "vm_disk_gb=$(VM_DISK_GB)"

kvm-setup: ## Configure host: KVM + VM + port forwarding
	cd ansible && ansible-playbook -i inventory/hosts.yml playbook-host.yml \
	  -e "vm_cpus=$(VM_CPUS)" \
	  -e "vm_memory_mb=$(VM_MEMORY_MB)" \
	  $(if $(TAGS),--tags $(TAGS),)

k8s-cluster: ## Run Kubespray to install K8s and form cluster across all VMs
	cd ansible && ansible-playbook -i inventory/k8s-cluster.yml \
	  playbook-k8s.yml \
	  -e "auto_renew_certificates=true"

k8s-config: ## Fetch kubeconfig from K8s control plane
	cd ansible && ansible-playbook -i inventory/hosts.yml playbook-host.yml --tags kubeconfig

helm-apply: ## Deploy Helm charts onto K8s
	KUBECONFIG=kubeconfig helmfile apply

deploy: kvm-setup k8s-cluster helm-apply ## Deploy to physical server

aws-deploy: tf-apply kvm-setup k8s-cluster helm-apply ## Full AWS deploy

validate: ## Validate Packer + Terraform configs
	cd packer && packer validate .
	cd terraform && terraform validate

help: ## Show this help
	@awk -F ':.*## ' '/^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

.PHONY: image tf-init tf-plan tf-apply tf-destroy kvm-setup k8s-cluster k8s-config helm-apply aws-deploy deploy install validate help
