# 部署指导

> 本文档提供在华为云上部署「云上浏览器开发环境」的可复现步骤。所有命令均在仓库根目录执行，`cd` 使用相对路径。

## 1. 环境准备

| 项 | 要求 |
|-|-|
| 华为云账号 | 具备 VPC / 子网 / 安全组 / 弹性公网 IP / ECS 的创建权限 |
| Terraform | `>= 1.5` |
| 区域 | `cn-north-4`（北京四） |
| 凭据准备 | 在华为云「我的凭证」页面获取 Access Key 与 Secret Access Key，不写入仓库 |

设置华为云凭据（请勿写入仓库或脚本）：

```bash
export HW_ACCESS_KEY="your-access-key"
export HW_SECRET_KEY="your-secret-key"
```

## 2. 配置变量

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

编辑 `terraform.tfvars`，至少完成两项修改：

- `allowed_cidr`：改为本机公网 IP 或办公网段（形如 `x.x.x.x/32`），切勿保留 `0.0.0.0/0`；
- `vscode_password`：设置为至少 12 位的强口令。

其余变量按需调整（规格、磁盘、带宽、可用区等）。

## 3. 初始化

```bash
terraform init
```

预期输出（节选）：

```text
Initializing the backend...
Initializing provider plugins...
- Finding huaweicloud/huaweicloud versions matching ">= 1.96"...
- Installing huaweicloud/huaweicloud ...
Terraform has been successfully initialized!
```

## 4. 预检（可选但推荐）

```bash
terraform validate
```

预期输出：

```text
Success! The configuration is valid.
```

## 5. 部署

```bash
terraform apply
```

输入 `yes` 确认。部署成功后输出（节选）：

```text
Apply complete! Resources: N added, 0 changed, 0 destroyed.

Outputs:

ecs_instance_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
eip_public_ip = "x.x.x.x"
vscode_access_url = "http://x.x.x.x:8080"
```

## 6. 验证

1. 记录 `terraform output` 中的 `vscode_access_url`（形如 `http://x.x.x.x:8080`）。
2. 在浏览器打开该地址。
3. 输入第 2 步设置的 `vscode_password`。
4. 看到浏览器版 VS Code 界面，并能打开终端、创建文件，即表示部署成功。

命令行快速连通性检查（可选）：

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://<弹性公网IP>:8080"
```

返回 `302`（重定向至登录页）或 `200` 均表示 `code-server` 已正常监听。

> 提示：实例首次启动需数分钟完成 `code-server` 与 Node.js 安装（国内网络下载安装包耗时较长），期间访问可能短暂不可达，属正常现象。若需分钟级就绪，可改用预置私有镜像（见 `infra/image-bake/README.md`）。

## 7. 常见问题

- **浏览器打不开访问地址**：确认 `allowed_cidr` 已包含本机公网 IP；确认本机确实从该公网 IP 出网；等待 1～2 分钟待用户数据脚本执行完成。
- **提示密码错误**：确认输入的是 `terraform.tfvars` 中设置的 `vscode_password`。
- **想修改访问端口**：修改 `infra/main.tf` 中安全组规则的 `port_range_min/max`、用户数据脚本中的 `bind-addr`，以及 `infra/outputs.tf` 中 `vscode_access_url` 的端口，保持一致。
