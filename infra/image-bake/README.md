# 私有镜像烘焙栈

本目录是一个**独立的 Terraform 栈**（独立状态文件），用于把 code-server 与
Node.js 预置进一台临时构建实例，再制作成华为云**系统盘私有镜像**。烘焙完成后
销毁构建栈，镜像保留，供 `../` 主栈通过 `private_image_id` 变量引用，从而：

- 运行时实例**无需开机下载** 233MB 的 code-server 安装包（国内网络直拉
  GitHub 极慢，曾出现 20 分钟以上未装完的情况）；
- 运行时开机仅做配置写入与服务启动，**分钟级就绪**；
- 软件版本随镜像固化，批量部署时实例状态一致。

## 使用步骤

```bash
export HW_ACCESS_KEY="<你的 AK>"
export HW_SECRET_KEY="<你的 SK>"

terraform init

# 第一步：仅创建构建实例并执行烘焙（安装 + 自检 + 清理）
terraform apply -var 'create_image=false'

# 等待烘焙完成。两种观察方式：
#   a) 设置 ntfy_topic 后，浏览器/curl 订阅 https://ntfy.sh/<topic> 收通知；
#   b) 控制台查看构建实例的 /var/log/cloud-init-output.log，
#      或 /root/.bake-result（内容为 ok 或失败详情）

# 第二步：基于已烘焙好的构建实例创建私有镜像（约 10~20 分钟）
terraform apply -var 'create_image=true'

# 获取镜像 ID，填入主栈 terraform.tfvars 的 private_image_id
terraform output image_id

# 第三步：销毁构建栈（VPC/子网/安全组/EIP/构建实例）；镜像默认保留
terraform destroy
```

## 注意事项

- **镜像同名冲突**：重复烘焙时请修改 `project_name`，或先在 IMS 控制台删除旧镜像。
- **版本升级**：修改 `code_server_version` / `node_version` 后重新走一遍流程；
  镜像名称带版本号，不会与旧镜像冲突。
- **临时性**：构建实例与 EIP 仅在烘焙期间存在（烘焙约 10~30 分钟）；镜像属闲置资源，验证完成后如不再使用请删除。
- 构建实例无需入方向安全组规则（只出不进），请勿为其添加入方向规则。
