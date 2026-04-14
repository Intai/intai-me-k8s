## Demo

Live at https://intai.me/

## Prerequisites

- Python 3.13
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Packer](https://developer.hashicorp.com/packer/install)
- [QEMU](https://www.qemu.org/download/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helmfile](https://helmfile.readthedocs.io/en/latest/#installation)

## AWS Deployment

1. Copy `.env.example` to `.env` and fill in values.
   | Variable | Description |
   |---|---|
   | `AWS_REGION` | AWS region to deploy in |
   | `AWS_AZ_COUNT` | Number of AWS availability zones to spread subnets across |
   | `DOMAIN_NAME` | Domain name for the web server |
   | `CERTBOT_EMAIL` | Email for Let's Encrypt certificate notifications |
   | `INSTANCE_TYPE` | EC2 instance type with nested virtualization (e.g. `c8i.large`) |
   | `PROJECT_NAME` | Identifier used for resource tagging |
   | `ENVIRONMENT` | Deployment environment (e.g. `production`) |
   | `VM_CPUS` | vCPUs allocated to each KVM guest |
   | `VM_MEMORY_MB` | Memory in MB allocated to each KVM guest |
   | `VM_DISK_GB` | Disk size in GB for each KVM guest |
   | `SERVER_COUNT` | Number of EC2 hosts to provision |
2. Create and activate a virtual environment.
   ```sh
   python3.13 -m venv .venv
   source .venv/bin/activate
   ```
3. `make install` to install dependencies (Ansible, Kubespray, Helm plugins).
4. `make image` to build a KVM base image with Packer, pre-configured with Ubuntu 24.04 and SSH hardening.
5. `aws configure` to set up AWS credentials for Terraform.
6. `make aws-deploy` to provision the full stack: Terraform infrastructure (VPC, EC2, Elastic IP, Route 53), KVM guests, WireGuard mesh, Kubernetes cluster via Kubespray, and Helm charts (Traefik, cert-manager, nginx).
7. `make verify` to verify deployment health across all layers.

### Scale Up

1. Increase `SERVER_COUNT` in `.env` (e.g. 3 → 5).
2. `make aws-deploy` to provision new nodes and join them to the cluster (existing nodes are untouched).

### Scale Down

1. `make k8s-remove-node NODE=node3` to drain workloads and remove the node from K8s/etcd.
2. Decrease `SERVER_COUNT` in `.env` (e.g. 3 → 2).
3. `make aws-deploy` to destroy the removed EC2 instance and re-sync the cluster.

## Bare-Metal Deployment

1. Follow steps 1-4 above.
2. Fill in `HOST1_IP` and `HOST2_IP` in `.env`, and update `ansible/inventory/hosts.yml` with your server details.
3. `make deploy` to configure KVM guests, WireGuard mesh, Kubernetes cluster, and Helm charts.
4. `make verify` to verify deployment health across all layers.

## Production Considerations

- **Route 53 DNS failover** — weighted routing with health checks per host, automatic removal of unhealthy nodes within 30-90 seconds.
- **WireGuard mesh networking** — encrypted tunnels between hosts for cross-node Kubernetes communication (API server, etcd, pod traffic).
- **Traefik DaemonSet** — ingress controller on every node, load balancing and providing redundancy for downstream pods.
- **cert-manager with Let's Encrypt** — automatic TLS certificate provisioning and renewal via HTTP-01 challenge.
- **Kubespray** — production-grade Kubernetes deployment with HA support.
- **CI/CD via GitHub Actions** — automatic Helm deployment on push to main.
