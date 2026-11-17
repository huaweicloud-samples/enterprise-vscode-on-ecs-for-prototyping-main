# 云上浏览器开发环境（华为云实践）

[![License: MIT-0](https://img.shields.io/badge/License-MIT--0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-华为云-blue.svg)](https://www.huaweicloud.com)
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://www.huaweicloud.com)

> 本仓库提供在华为云上一键拉起「浏览器内集成开发环境」的 Terraform 实践：一台弹性云服务器自动安装并启动浏览器版 VS Code 与 Node.js 运行时，开发者从任意设备的浏览器即可获得完整的云端开发体验。

## 1. 简介

本实践在华为云上创建一台公网可达的弹性云服务器（ECS），实例首次启动时自动完成浏览器版 VS Code（`code-server`）与 Node.js 运行时的安装，并以 systemd 服务方式常驻运行。适用于快速搭建云上验证环境、演示环境或临时开发机，无需在本地安装集成开发环境。

## 2. 目录

- `docs/`：架构说明、部署指导
- `infra/`：Terraform 配置（huaweicloud Provider）
- `infra/image-bake/`：私有镜像烘焙栈（可选，预装软件实现秒级启动）

## 3. 架构图

```text
浏览器 ── http://<弹性公网IP>:8080 ──▶ 安全组(仅放行 8080) ──▶ ECS
                                                              │ 弹性云服务器
                                                              ├─ code-server :8080（密码认证）
                                                              └─ Node.js 20.11.0
```

架构细节见 [docs/architecture.md](docs/architecture.md)。

## 4. 方案亮点

- **一键部署**：一条 `terraform apply` 拉起完整环境，实例开机自动完成软件安装与服务启动。
- **浏览器即用**：无需本地 IDE，任意设备通过浏览器进入开发环境，自带终端与文件管理。
- **配置清晰**：规格、磁盘、端口、访问口令等均通过变量显式管理，便于按需调整。
- **收敛的网络暴露**：仅放行单端口，来源受 IP 段约束。

## 5. 涉及云服务

本实践涉及以下华为云服务：

- 虚拟私有云（VPC）/ 子网
- 安全组
- 弹性云服务器（ECS）
- 弹性公网 IP（EIP）

> 使用完毕后请执行清理，及时释放资源，避免残留。

## 6. 前置条件

- 华为云账号，且具备 VPC / 子网 / 安全组 / 弹性公网 IP / ECS 的创建权限。
- 本地已安装 Terraform `>= 1.5`。
- 目标区域为 `cn-north-4`（北京四），可用区为 `cn-north-4a`。
- 已在华为云「我的凭证」页面获取 Access Key 与 Secret Access Key，凭据不写入任何文件。

## 7. 快速开始

```bash
# 1. 设置华为云凭据（请勿写入仓库）
export HW_ACCESS_KEY="your-access-key"
export HW_SECRET_KEY="your-secret-key"

# 2. 配置变量
cd infra
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars：将 allowed_cidr 收紧为本机公网 IP，并设置 vscode_password

# 3. 初始化并部署
terraform init
terraform apply
```

部署成功后执行 `terraform output`，记录 `vscode_access_url`。

## 8. 分步部署

1. **准备凭据**：导出 `HW_ACCESS_KEY` 与 `HW_SECRET_KEY`。
2. **配置变量**：`cd infra && cp terraform.tfvars.example terraform.tfvars`，编辑 `terraform.tfvars`。
3. **初始化**：`terraform init`，预期输出 `Terraform has been successfully initialized!`。
4. **预检**：`terraform validate`，预期输出 `Success! The configuration is valid.`。
5. **部署**：`terraform apply`，输入 `yes` 确认，预期输出 `Apply complete!`。

逐步说明与预期输出详见 [docs/deployment-guide.md](docs/deployment-guide.md)。

## 9. 使用方法

1. 执行 `terraform output`，获取 `vscode_access_url`（形如 `http://x.x.x.x:8080`）。
2. 在浏览器打开该地址。
3. 输入部署时设置的 `vscode_password`。
4. 进入浏览器版 VS Code，可打开终端、编辑与运行代码。

命令行连通性检查（可选）：

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://<弹性公网IP>:8080"
```

返回 `200` 表示服务已正常监听。

> **验证提醒**：部署完成后，请按本节步骤自行验证，确认浏览器可正常打开并登录、终端可用，即视为交付完成。实例首次启动需 1～2 分钟完成软件安装，期间访问可能短暂不可达，属正常现象。

## 10. 清理资源

```bash
cd infra
terraform destroy
```

输入 `yes` 确认，即可释放本次实践创建的全部资源，避免残留。

## 11. 详细说明

- 实例用户数据脚本完成：安装 `code-server`（`https://code-server.dev/install.sh`）、通过 `nvm` 安装 Node.js `20.11.0`、写入 `code-server` 配置（`bind-addr: 0.0.0.0:8080`、密码认证）、注册并启动 systemd 服务。
- 访问密码以敏感变量 `vscode_password` 传入，写入实例内 `/root/.config/code-server/config.yaml`。
- 华为云 Ubuntu 镜像默认用户为 `root`（无 `ubuntu` 用户），脚本全程以 root 运行。
- **预置私有镜像（可选，秒级启动）**：默认路径开机时需从公网下载约 233MB 的 `code-server` 安装包，国内网络耗时较长。可先用 `infra/image-bake/` 烘焙栈预装 `code-server` 与 Node.js 并制作系统盘私有镜像，再将 `terraform output image_id` 填入主栈变量 `private_image_id`。此时开机脚本检测到软件已就绪即跳过安装，仅写入配置并启动服务，分钟级可用；两种路径共用同一份用户数据脚本（按 `command -v` 自动判断），无需改动主栈代码。

完整架构与配置项说明见 [docs/architecture.md](docs/architecture.md)。

## 12. 依赖

- [code-server](https://coder.com)：浏览器版 VS Code 开源项目。
- [nvm](https://github.com/nvm-sh/nvm)：Node.js 版本管理。
- [Terraform huaweicloud Provider](https://registry.terraform.io/providers/huaweicloud/huaweicloud/latest)：华为云基础设施编排。

## 13. FAQ

**Q：浏览器打不开访问地址？**
A：确认 `allowed_cidr` 已包含本机公网 IP；确认本机从该公网 IP 出网；等待数分钟待安装完成。

**Q：首次启动较久，想更快就绪？**
A：默认路径开机需下载约 233MB 的 `code-server` 安装包，国内网络耗时较长。可用 `infra/image-bake/` 预烘焙私有镜像并设置 `private_image_id`，实例启动时跳过安装，分钟级可用（详见该目录 README）。

**Q：提示密码错误？**
A：确认输入的是 `terraform.tfvars` 中设置的 `vscode_password`。

**Q：如何更换访问端口？**
A：同步修改安全组规则端口、用户数据脚本中的 `bind-addr` 与 `outputs.tf` 中访问地址端口，保持一致。

**Q：如何降低公网暴露面？**
A：将 `allowed_cidr` 收紧为固定 IP 段，并启用强口令。

## 14. 贡献指南

欢迎通过 Issue 与 Pull Request 参与改进。贡献前请确保 `terraform validate` 通过，并遵循本仓库的目录与文档约定。

## 15. 许可证

本实践采用 [MIT No Attribution](LICENSE) 许可证（Copyright Huawei Cloud. All Rights Reserved）。

## 16. 联系方式

- 如遇到问题或有改进建议，欢迎通过华为云开发者社区反馈交流。

## 17. 创建者与维护者

| 项 | 内容 |
|---|---|
| **创建者** | zhangcheng123321 |
| **维护者** | zhangcheng123321 |

> 上表为本仓库创建者与维护者账号。
