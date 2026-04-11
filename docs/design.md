# Infrastructure-as-Code: Packer + KVM + Kubespray + Helm for Kubernetes on EC2

## Context

Deploy the intai.me website (nginx serving a CV page) as a Kubernetes pod running inside a KVM virtual machine. The host is an AWS EC2 c8i.large instance (8th-gen Intel with nested virtualization support), but the design is portable to any physical Linux server with KVM. Packer builds a QEMU/KVM image with K8s software pre-installed (kubelet, kubeadm, containerd). Ansible configures the host, launches the VM, and runs Kubespray post-deploy to form the cluster. Helm deploys nginx and cert-manager. Terraform provisions the AWS infrastructure only. The design supports multi-server deployments — each server runs a KVM VM, and Kubespray joins them into a single K8s cluster.

## Traffic Flow

```
Internet
  │
  ▼
EC2 / Physical Host (Elastic IP or public IP)
  │  ports 80, 443
  │  iptables DNAT
  ▼
KVM VM (192.168.122.x on libvirt virbr0)
  │  ports 80, 443
  ▼
Kubernetes (single-node cluster)
  │
  ├─ ingress-nginx (hostNetwork: true)
  │    │
  │    ├─ nginx pod (intai.me site)
  │    └─ cert-manager (Let's Encrypt HTTPS)
  │
  └─ cluster services (CoreDNS, kube-proxy, etc.)
```

## Directory Structure

```
intai-me-k8s/
├── .env.example                    # Committed — documents all required variables
├── .env                            # Gitignored — actual values
├── pyproject.toml                  # Python deps: ansible, boto3
├── helmfile.yaml                   # Declarative multi-chart deployment
├── Makefile
├── .gitignore
├── docs/
│   └── design.md                   # This file
├── site/
│   ├── index.html                  # Landing page with iframe rendering cv.pdf
│   └── cv.pdf                      # CV document
├── packer/
│   ├── k8s-node.pkr.hcl            # QEMU builder — produces qcow2 image
│   ├── variables.pkr.hcl
│   └── http/
│       ├── meta-data                # cloud-init metadata (empty)
│       └── user-data                # cloud-init autoinstall config
├── ansible/
│   ├── requirements.yml             # Kubespray Ansible collection pinned to v2.30.0
│   ├── inventory/
│   │   ├── hosts.yml                # Host inventory (EC2 IP or physical server IP)
│   │   └── k8s-cluster.yml          # Kubespray inventory (VM IPs for cluster formation)
│   ├── playbook-host.yml            # Configures host: KVM + VM + port forwarding
│   ├── playbook-k8s.yml             # Imports kubespray collection playbook
│   └── roles/
│       ├── kvm_host/
│       │   └── tasks/main.yml       # Install KVM/QEMU/libvirt, enable services
│       ├── vm_provision/
│       │   ├── tasks/main.yml       # Copy qcow2, define VM via libvirt, start VM
│       │   ├── templates/
│       │   │   └── vm-domain.xml.j2 # libvirt VM definition
│       │   └── defaults/main.yml    # VM resource defaults (vCPU, RAM, disk)
│       └── port_forward/
│           └── tasks/main.yml       # iptables DNAT 80/443 from host to VM
├── helm/
│   └── nginx-site/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── configmap.yaml       # Site content (index.html)
│           └── cluster-issuer.yaml  # cert-manager Let's Encrypt issuer
├── .github/
│   └── workflows/
│       └── deploy-apps.yml          # GitHub Actions: deploy Helm charts on push
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    └── modules/
        ├── vpc/
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        ├── security/
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── compute/
            ├── main.tf
            ├── variables.tf
            └── outputs.tf
```

## Implementation Plan

### Phase 1: Scaffolding & Web Content

- Create `pyproject.toml` with dependencies: `ansible`, `boto3`
- Create `.env.example`:
  ```
  AWS_REGION=ap-southeast-2
  DOMAIN_NAME=intai.me
  CERTBOT_EMAIL=admin@intai.me
  INSTANCE_TYPE=c8i.large
  PROJECT_NAME=intai-me-k8s
  ENVIRONMENT=production
  SSH_USERNAME=packer
  SSH_PASSWORD=packer
  VM_CPUS=1
  VM_MEMORY_MB=2048
  VM_DISK_GB=20
  ```
- Create `.gitignore` (tfstate, .terraform/, .env, .venv/, *.qcow2, output-*)
- Create `site/index.html` — minimal HTML with full-viewport `<iframe>` rendering `cv.pdf`
- Place `cv.pdf` directly in `site/`
- Create `ansible/requirements.yml` — Kubespray as Ansible collection pinned to `v2.30.0`

### Phase 2: Packer — KVM Base Image (`packer/`)

Packer uses the QEMU builder to produce a clean Ubuntu qcow2 image. Kubespray handles all K8s prerequisites (swap, kernel modules, sysctl) and installation post-deploy — no shell provisioner needed.

- **k8s-node.pkr.hcl**:
  - `source "qemu"` block:
    - `iso_url`: Ubuntu 24.04 Server ISO
    - `iso_checksum`: SHA256 from Ubuntu releases
    - `disk_size`: `20G`
    - `format`: `qcow2`
    - `accelerator`: `kvm` (macOS: `hvf`; CI/Linux: `kvm`)
    - `http_directory`: `http/` (serves cloud-init)
    - `boot_command`: autoinstall kernel params pointing to cloud-init HTTP server
    - `ssh_username`/`ssh_password`: for Packer provisioner access
    - `shutdown_command`: `sudo shutdown -P now`
  - No provisioners — cloud-init handles all OS setup during install
  - Output: `output-k8s-node/k8s-node.qcow2`

- **variables.pkr.hcl**: `ubuntu_iso_url`, `ubuntu_iso_checksum`, `disk_size`, `ssh_username`, `ssh_password`

- **http/user-data**: cloud-init autoinstall config — sets up SSH user, enables password auth for Packer, minimal packages

### Phase 3: Ansible — Host Configuration (`ansible/`)

Ansible configures any Linux host (EC2 or physical) to run the KVM VM.

#### Role: `kvm_host`
1. Install packages: `qemu-kvm`, `libvirt-daemon-system`, `virtinst`, `libguestfs-tools`, `iptables-persistent`
2. Enable and start `libvirtd` service
3. Verify nested KVM support: check `/sys/module/kvm_intel/parameters/nested` is `Y`
4. Ensure libvirt default network (virbr0, 192.168.122.0/24) is active
5. Rate limiting on SSH (22) and K8s API (6443) — drop IPs with more than 5 new connections per 60 seconds:
   ```
   iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --set
   iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --name ssh --update --seconds 60 --hitcount 5 -j DROP
   iptables -A INPUT -p tcp --dport 6443 -m conntrack --ctstate NEW -m recent --name k8sapi --set
   iptables -A INPUT -p tcp --dport 6443 -m conntrack --ctstate NEW -m recent --name k8sapi --update --seconds 60 --hitcount 5 -j DROP
   ```

#### Role: `vm_provision`
1. Copy Packer-built qcow2 image to `/var/lib/libvirt/images/k8s-node.qcow2`
2. Use `virt-customize` to inject SSH key and set static IP (192.168.122.10) via cloud-init/netplan
3. Define VM from `vm-domain.xml.j2` template via `virsh define`:
   - vCPUs: `{{ vm_cpus }}` (default: 1)
   - Memory: `{{ vm_memory_mb }}` MB (default: 2048)
   - Disk: the qcow2 image
   - Network: libvirt default (virbr0)
   - Boot: direct kernel boot or standard BIOS
4. Start VM via `virsh start`, wait for SSH to become available
5. Add VM to in-memory Ansible inventory for subsequent plays

#### Role: `port_forward`
1. Enable IP forwarding: `sysctl net.ipv4.ip_forward=1`
2. iptables DNAT rules:
   ```
   iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.122.10:80
   iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 192.168.122.10:443
   iptables -t nat -A PREROUTING -p tcp --dport 6443 -j DNAT --to-destination 192.168.122.10:6443
   iptables -t nat -A POSTROUTING -o virbr0 -j MASQUERADE
   iptables -A FORWARD -p tcp -d 192.168.122.10 --dport 80 -j ACCEPT
   iptables -A FORWARD -p tcp -d 192.168.122.10 --dport 443 -j ACCEPT
   iptables -A FORWARD -p tcp -d 192.168.122.10 --dport 6443 -j ACCEPT
   ```
3. Persist rules via `iptables-persistent` / `netfilter-persistent save`

#### Playbook: `playbook-host.yml`
```yaml
- hosts: hosts
  become: true
  roles:
    - kvm_host
    - vm_provision
    - port_forward
```

### Phase 4: Kubespray — K8s Install & Cluster Formation (post-deploy)

After all hosts are provisioned and VMs are running, Kubespray runs once to install K8s software and form the cluster across all VMs. This is the standard Kubespray workflow — one playbook does everything.

#### Install Kubespray collection

```shell
ansible-galaxy install -r ansible/requirements.yml
```

#### `ansible/requirements.yml`
```yaml
collections:
  - name: https://github.com/kubernetes-sigs/kubespray
    type: git
    version: v2.30.0
```

#### `ansible/playbook-k8s.yml`
```yaml
- name: Install Kubernetes
  ansible.builtin.import_playbook: kubernetes_sigs.kubespray.cluster
```

#### Inventory (`ansible/inventory/k8s-cluster.yml`)
Generated or maintained manually based on deployed VMs:
```yaml
all:
  hosts:
    node1:
      ansible_host: 192.168.122.10    # VM on server 1
      ip: 192.168.122.10
    # node2:                          # VM on server 2 (future)
    #   ansible_host: 192.168.122.10
    #   ip: 192.168.122.10
    #   ansible_ssh_host: 5.6.7.8     # jump through server 2's public IP
  children:
    kube_control_plane:
      hosts:
        node1: {}
    kube_node:
      hosts:
        node1: {}
    etcd:
      hosts:
        node1: {}
    k8s_cluster:
      children:
        kube_control_plane: {}
        kube_node: {}
```

#### Kubespray vars:
- `container_manager: containerd`
- `kube_network_plugin: calico` (or flannel)
- `auto_renew_certificates: true`

#### Scaling to multiple servers:
1. Add new host entries to the inventory
2. For cross-server communication, VMs need network connectivity (VPN/WireGuard or same LAN)
3. Re-run Kubespray — it handles joining new nodes to the existing cluster

### Phase 5: Helm Chart — nginx Site (`helm/nginx-site/`)

- **Chart.yaml**: name `nginx-site`, version `0.1.0`
- **values.yaml**:
  ```yaml
  domain: intai.me
  certEmail: admin@intai.me
  replicaCount: 1
  image:
    repository: nginx
    tag: "1.28-alpine"
  ```
- **templates/configmap.yaml**: mounts `index.html` content and `cv.pdf` as binary data
- **templates/deployment.yaml**: nginx pod mounting the ConfigMap at `/usr/share/nginx/html`
- **templates/service.yaml**: ClusterIP service on port 80
- **templates/ingress.yaml**: ingress-nginx resource for `{{ .Values.domain }}` with TLS annotation for cert-manager
- **templates/cluster-issuer.yaml**: cert-manager `ClusterIssuer` using Let's Encrypt HTTP-01 solver

#### Dependencies (deployed via Makefile or GitHub Actions):
- **ingress-nginx**: Helm chart deployed with `hostNetwork: true` so it binds directly to VM ports 80/443
- **cert-manager**: Helm chart + CRDs for automatic Let's Encrypt certificates

### Phase 6: Helm Deployment — Helmfile

All Helm releases are declared in `helmfile.yaml` at the repo root. `helmfile apply` replaces multiple `helm upgrade --install` commands — the Helm equivalent of `kubectl apply` with kustomization.

#### `helmfile.yaml`
```yaml
repositories:
  - name: jetstack
    url: https://charts.jetstack.io
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx

helmDefaults:
  kubeconfig: kubeconfig

releases:
  - name: cert-manager
    namespace: cert-manager
    createNamespace: true
    chart: jetstack/cert-manager
    set:
      - name: crds.enabled
        value: "true"

  - name: ingress-nginx
    namespace: ingress-nginx
    createNamespace: true
    chart: ingress-nginx/ingress-nginx
    needs:
      - cert-manager/cert-manager
    set:
      - name: controller.hostNetwork
        value: "true"
      - name: controller.dnsPolicy
        value: ClusterFirstWithHostNet

  - name: nginx-site
    chart: ./helm/nginx-site
    needs:
      - ingress-nginx/ingress-nginx
    values:
      - domain: {{ requiredEnv "DOMAIN_NAME" }}
        certEmail: {{ requiredEnv "CERTBOT_EMAIL" }}
```

The `needs:` directive ensures ordering: cert-manager CRDs exist before nginx-site creates a `ClusterIssuer`.

#### Makefile (`make helm-apply`) — manual/local deploys
1. Fetch kubeconfig from KVM VM (via `make k8s-config`) — contains client cert, key, and CA for API auth
2. `helmfile apply` — installs/upgrades all releases in dependency order

#### GitHub Actions (`.github/workflows/deploy-apps.yml`) — CI/CD on push
- Triggers on push to `main` (changes to `helm/`, `site/`, or `helmfile.yaml`)
- Sets up kubectl/helm/helmfile with kubeconfig from GitHub Secrets (`KUBECONFIG_B64` — base64-encoded)
- Connects directly to K8s API at `https://<EIP>:6443` (client cert auth, same as managed K8s)
- No SSH access needed — more secure than giving CI shell access to the server
- Runs `helmfile apply`
- **Secret rotation**: update `KUBECONFIG_B64` in GitHub Secrets every ~10 months when K8s certs auto-renew (run `make k8s-config` locally, re-encode and update the secret)

### Phase 7: Terraform Modules — AWS Infrastructure Only (`terraform/`)

Terraform provisions the AWS environment. Identical structure to the original project but uses a stock Ubuntu AMI (no custom AMI).

#### VPC Module (`modules/vpc/`)
- VPC `10.0.0.0/16` with DNS support/hostnames enabled
- 2 public subnets (`10.0.1.0/24`, `10.0.2.0/24`) across 2 AZs
- Internet gateway + public route table
- Outputs: `vpc_id`, `public_subnet_ids`

#### Security Module (`modules/security/`)
- Security group:
  - Ingress 80 from `0.0.0.0/0` (HTTP — Let's Encrypt + redirect)
  - Ingress 443 from `0.0.0.0/0` (HTTPS)
  - Ingress 6443 from `0.0.0.0/0` (K8s API — authenticated via client certificate)
  - Ingress 22 from `0.0.0.0/0` (SSH — key-based auth)
  - Egress all
- Outputs: `instance_sg_id`

#### Compute Module (`modules/compute/`)
- `data "aws_ami"` lookup for latest Ubuntu 24.04 official AMI (`099720109477` Canonical owner)
- `aws_instance` c8i.large:
  - Encrypted gp3 root volume (30 GB to accommodate host + KVM image)
  - IMDSv2 enforced (`http_tokens = "required"`)
  - SSH key pair for access
- `aws_eip` for stable public IP
- Outputs: `instance_id`, `public_ip`, `elastic_ip`

#### Root Module
- **providers.tf**: AWS provider, local state
- **variables.tf**: `aws_region`, `project_name`, `environment`, `domain_name`, `instance_type`
- **main.tf**: Compose vpc → security → compute modules
- **outputs.tf**: Surface instance IP, EIP, VPC ID

### Phase 8: Makefile

```makefile
include .env
export

# --- Image ---
image:                              ## Build KVM base image with Packer
	cd packer && packer build \
	  -var "ssh_username=$(SSH_USERNAME)" \
	  -var "ssh_password=$(SSH_PASSWORD)" \
	  k8s-node.pkr.hcl

# --- AWS Infrastructure (skip for physical servers) ---
tf-init:                            ## Terraform init
	cd terraform && terraform init

tf-plan:                            ## Terraform plan
	cd terraform && terraform plan -var "instance_type=$(INSTANCE_TYPE)" ...

tf-apply:                           ## Terraform apply — provision AWS
	cd terraform && terraform apply -auto-approve ...

tf-destroy:                         ## Terraform destroy
	cd terraform && terraform destroy -auto-approve ...

# --- KVM Setup (works on EC2 or physical server) ---
kvm-setup:                          ## Configure host: KVM + VM + port forwarding
	cd ansible && ansible-playbook -i inventory/hosts.yml playbook-host.yml

# --- Cluster Formation (run after all hosts are provisioned) ---
k8s-cluster:                        ## Run Kubespray to install K8s and form cluster across all VMs
	cd ansible && ansible-playbook -i inventory/k8s-cluster.yml \
	  playbook-k8s.yml \
	  -e "auto_renew_certificates=true"

k8s-config:                         ## Fetch kubeconfig from K8s control plane (re-run annually after cert auto-renewal)
	cd ansible && ansible-playbook -i inventory/hosts.yml playbook-host.yml --tags kubeconfig

# --- Application Deployment ---
helm-apply:                         ## Deploy Helm charts onto K8s
	helmfile apply

# --- Full Deploy ---
aws-deploy: tf-apply kvm-setup k8s-cluster helm-apply  ## Full AWS deploy (Terraform + Ansible + Kubespray + Helm)

deploy: kvm-setup k8s-cluster helm-apply  ## Deploy to physical server (Ansible + Kubespray + Helm only)

# --- Utilities ---
install:                            ## Install Python + Ansible dependencies
	pip install -e .
	ansible-galaxy install -r ansible/requirements.yml

validate:                           ## Validate Packer + Terraform configs
	cd packer && packer validate k8s-node.pkr.hcl
	cd terraform && terraform validate
```

## Resource Allocation

| Resource | EC2 Host (c8i.large) | KVM VM       |
|----------|----------------------|--------------|
| vCPUs    | 2                    | 1            |
| Memory   | 4 GB                 | 2 GB         |
| Disk     | 30 GB gp3            | 20 GB qcow2  |
| Network  | Public (EIP)         | 192.168.122.10 (virbr0) |

## Key Design Decisions

1. **No AMI — portable to physical servers**: Packer builds a qcow2 KVM image, not an AWS AMI. The same image runs on EC2 or any Linux server with KVM. Terraform is AWS-only; Ansible handles everything else.
2. **Kubespray does everything post-deploy**: Packer builds a clean Ubuntu image with OS prerequisites only. Kubespray handles full K8s install + cluster formation in one run — the standard workflow. Same image works for single-node or multi-node, just change the inventory.
3. **KVM on c8i.large (nested virtualization)**: 8th-gen Intel EC2 instances expose the `vmx` CPU flag, enabling KVM inside EC2 without expensive bare-metal instances.
4. **Port forwarding via iptables**: Host forwards ports 80/443 to the KVM VM's static IP on the libvirt bridge. ingress-nginx runs with `hostNetwork: true` inside K8s to receive traffic directly.
5. **cert-manager replaces certbot**: In Kubernetes, cert-manager handles Let's Encrypt certificates natively via Ingress annotations — no systemd timers or first-boot scripts.
6. **Auto-renewing K8s certificates**: Kubespray's `auto_renew_certificates: true` sets up a systemd timer to renew certs before they expire (default 1 year). Re-fetch kubeconfig annually via `make k8s-config`.
7. **Kubespray as Ansible Collection**: Installed via `ansible-galaxy` from `ansible/requirements.yml`, pinned to `v2.30.0`. Cleaner than a git submodule — no 50MB+ directory in the repo, standard Ansible dependency management, and the officially recommended approach.
7. **IMDSv2 enforced**: Prevents SSRF credential theft on the EC2 host.
8. **SSH for remote access**: Works on both EC2 and physical servers. Key-based auth only. No AWS-specific dependencies (SSM) for host access.

## Verification

1. `make validate` — runs `packer validate` and `terraform validate`
2. `make image` — builds qcow2 image with K8s software pre-installed
3. `make tf-init && make tf-plan` — review Terraform plan
4. `make aws-deploy` — full AWS deployment (Terraform + Ansible + Helm)
5. Verify via SSH:
   - `virsh list` — VM is running
   - `ssh 192.168.122.10 kubectl get nodes` — K8s node is Ready
   - `ssh 192.168.122.10 kubectl get pods -A` — nginx + cert-manager pods running
   - `curl -I http://localhost` — nginx responds
6. Point DNS A record to Elastic IP, verify HTTPS works
7. `make tf-destroy` — clean up AWS resources
8. For physical server: `make deploy` — same result without Terraform
