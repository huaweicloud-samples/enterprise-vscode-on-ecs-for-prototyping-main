# Browser-based Development Environment on Huawei Cloud

[![License: MIT-0](https://img.shields.io/badge/License-MIT--0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Huawei%20Cloud-blue.svg)](https://www.huaweicloud.com)
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://www.huaweicloud.com)

> This repository provides a Terraform practice on Huawei Cloud that starts a browser-based IDE with one command. An Elastic Cloud Server (ECS) installs and launches code-server plus the Node.js runtime on first boot, so developers get a complete development environment from any device with a browser.

## 1. Overview

A public-facing ECS is created on Huawei Cloud. On its first boot, the instance installs the browser edition of VS Code (code-server) and the Node.js runtime, then runs code-server as a systemd service. This is suitable for quickly setting up a verification environment, a demo environment, or a temporary development machine without a local IDE.

## 2. Highlights

- **One-command setup**: a single `terraform apply` creates the whole environment; software installation and service startup happen automatically on first boot.
- **Browser ready**: no local IDE is needed; the environment ships with a terminal and a file manager.
- **Explicit configuration**: instance flavor, disk, port, and access password are all managed as variables.
- **Narrow network exposure**: only one port is opened, and the source range is restricted.

## 3. Architecture

```text
Browser -- http://x.x.x.x:8080 --> Security Group (8080 only) --> ECS
                                                              | code-server :8080 (password)
                                                              | Node.js 20.11.0
```

See [docs/architecture.md](docs/architecture.md) for the resource list and configuration details.

An optional image bake stack under `infra/image-bake/` preinstalls both tools into a private system disk image, so the runtime instance skips downloads on boot and becomes ready in about a minute.

## 4. Cloud Services Used

- Virtual Private Cloud (VPC) and subnet
- Security group
- Elastic Cloud Server (ECS)
- Elastic IP (EIP)

Run the cleanup step after use to release all resources.

## 5. Prerequisites

- A Huawei Cloud account with permission to create a VPC, subnet, security group, EIP, and ECS.
- Terraform 1.5 or newer.
- Region `cn-north-4` (Beijing 4), availability zone `cn-north-4a`.
- Obtain the Access Key ID and Secret Access Key from the My Credentials page in the Huawei Cloud console. Keep them out of the repository.

## 6. Quick Start

```bash
# 1. Set credentials in your local terminal
export HW_ACCESS_KEY="your-access-key"
export HW_SECRET_KEY="your-secret-key"

# 2. Configure variables
cd infra
cp terraform.tfvars.example terraform.tfvars

# 3. Initialize and deploy
terraform init
terraform apply
```

Then run `terraform output` and record `vscode_access_url`.

## 7. Deployment

1. Export `HW_ACCESS_KEY` and `HW_SECRET_KEY`.
2. Copy `terraform.tfvars.example` to `terraform.tfvars`, set `vscode_password`, and narrow `allowed_cidr` to your own public IP range.
3. Run `terraform init`; expect `Terraform has been successfully initialized!`.
4. Run `terraform validate`; expect `Success! The configuration is valid.`.
5. Run `terraform apply`, confirm with `yes`; expect `Apply complete!`.

Step-by-step notes and expected output are in [docs/deployment-guide.md](docs/deployment-guide.md).

## 8. Usage

1. Run `terraform output` to read `vscode_access_url` (for example `http://x.x.x.x:8080`).
2. Open that address in a browser.
3. Enter the `vscode_password` set during deployment.
4. Open a terminal in the IDE and create or run a file to confirm the environment works.

Connectivity check:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://x.x.x.x:8080"
```

A `200` or `302` response means code-server is listening. First boot needs one to two minutes to finish installation.

## 9. Cleanup

```bash
cd infra
terraform destroy
```

Confirm with `yes` to release every resource created by Terraform and avoid leftovers.

## 10. FAQ

**Q: The browser cannot open the address?**
A: Make sure `allowed_cidr` includes your public IP, wait a few minutes for installation, and check the security group rule.

**Q: First boot is slow?**
A: The default path downloads the code-server package at boot. Use the `infra/image-bake/` stack and set `private_image_id` to skip installation.

**Q: Password rejected?**
A: Check the `vscode_password` value in `terraform.tfvars`.

## 11. License

Released under [MIT No Attribution](LICENSE) (Copyright Huawei Cloud. All Rights Reserved).

## 12. Contact

Questions and suggestions are welcome through the Huawei Cloud developer community.

## 13. Creator and Maintainer

| Item | Value |
|---|---|
| **Creator** | zhangcheng123321 |
| **Maintainer** | zhangcheng123321 |

The table above lists the creator and maintainer accounts for this repository.
