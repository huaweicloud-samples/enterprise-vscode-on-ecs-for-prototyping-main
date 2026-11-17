# ============================================================================
# 私有镜像烘焙栈（独立 Terraform 状态，与 infra/ 主栈分离）
#
# 用途：创建一台临时"构建实例"，在其上预装 code-server 与 Node.js，
#       烘焙完成后制作成系统盘私有镜像；构建栈销毁后镜像仍然保留，
#       供 infra/ 主栈通过 private_image_id 引用，实现实例秒级启动
#       （无需开机下载 233MB 安装包，规避国内网络拉取 GitHub 过慢的问题）。
#
# 两阶段用法：
#   1) terraform init
#   2) terraform apply -var 'create_image=false'
#      → 仅创建构建实例并执行烘焙（user_data 自动完成安装与自检）
#      → 等待烘焙完成：设置 ntfy_topic 可接收完成通知；也可在控制台查看
#        /var/log/cloud-init-output.log 或构建实例内 /root/.bake-result
#   3) terraform apply -var 'create_image=true'
#      → 基于已烘焙好的构建实例创建私有镜像（约 10~20 分钟）
#      → terraform output image_id  （供 infra/ 主栈引用）
#   4) terraform destroy
#      → 销毁构建实例与网络资源；私有镜像默认保留，按需在 IMS 控制台删除
#
# 注意：部署前请在华为云「我的凭证」页面获取 Access Key 与 Secret Access Key，
#       并仅在本机终端设置 HW_ACCESS_KEY / HW_SECRET_KEY；切勿写入本目录。
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.96"
    }
  }
}

provider "huaweicloud" {
  region = var.region
}

# ---------------------------------------------------------------------------
# 变量
# ---------------------------------------------------------------------------

variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "资源命名前缀（重复烘焙时请修改，避免镜像同名冲突）"
  type        = string
  default     = "vscode-bake"
}

variable "availability_zone" {
  description = "可用区完整名称"
  type        = string
  default     = "cn-north-4a"
}

variable "flavor_id" {
  description = "构建实例规格（2 核 4 GB 即可满足烘焙）"
  type        = string
  default     = "s6.large.2"
}

variable "volume_size" {
  description = "构建实例系统盘容量（GiB）；镜像最小磁盘随之确定"
  type        = number
  default     = 40
}

variable "system_disk_type" {
  description = "系统盘类型"
  type        = string
  default     = "GPSSD"
}

variable "bandwidth_size" {
  description = "构建实例弹性公网 IP 带宽（Mbit/s），越大下载越快"
  type        = number
  default     = 10
}

variable "image_name_regex" {
  description = "构建实例基础镜像名称正则（与主栈保持一致）"
  type        = string
  default     = "^Ubuntu 22.04 server 64bit$"
}

variable "vpc_cidr" {
  description = "烘焙栈 VPC 网段"
  type        = string
  default     = "10.9.0.0/16"
}

variable "subnet_cidr" {
  description = "烘焙子网网段"
  type        = string
  default     = "10.9.1.0/24"
}

variable "subnet_gateway" {
  description = "子网网关"
  type        = string
  default     = "10.9.1.1"
}

variable "code_server_version" {
  description = "预置的 code-server 版本"
  type        = string
  default     = "4.141.0"
}

variable "node_version" {
  description = "预置的 Node.js 版本"
  type        = string
  default     = "20.11.0"
}

variable "ntfy_topic" {
  description = "可选：烘焙完成后向该 ntfy.sh 主题推送结果通知；留空则不推送"
  type        = string
  default     = ""
}

variable "create_image" {
  description = "是否基于构建实例创建私有镜像（烘焙完成后置为 true 再 apply 一次）"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# 网络：构建实例只需出网，入方向无需规则
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = var.subnet_cidr
  gateway_ip = var.subnet_gateway
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "镜像烘焙构建实例安全组：仅需出网，不放入方向规则"
}

# 构建实例弹性公网 IP：供构建实例出网下载安装包
resource "huaweicloud_vpc_eip" "bake" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "${var.project_name}-bw"
    size        = var.bandwidth_size
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

data "huaweicloud_images_image" "ubuntu" {
  name_regex  = var.image_name_regex
  most_recent = true
}

# ---------------------------------------------------------------------------
# 构建实例：user_data 完成预装、自检、清理，并在结尾按需推送通知
# ---------------------------------------------------------------------------

resource "huaweicloud_compute_instance" "builder" {
  name              = "${var.project_name}-builder"
  flavor_id         = var.flavor_id
  availability_zone = var.availability_zone
  image_id          = data.huaweicloud_images_image.ubuntu.id

  security_group_ids = [huaweicloud_networking_secgroup.main.id]

  system_disk_type = var.system_disk_type
  system_disk_size = var.volume_size

  # 销毁前先停机，避免带病删除导致镜像/磁盘残留
  stop_before_destroy = true

  network {
    uuid = huaweicloud_vpc_subnet.main.id
  }

  user_data = <<-EOT
    #!/bin/bash
    # 构建实例烘焙脚本：预装 code-server 与 Node.js，自检后按需推送通知
    set -u
    export DEBIAN_FRONTEND=noninteractive
    sleep 10

    # 下载地址在此处由 Terraform 渲染为字面量，避免 Shell 变量名与模板语法冲突
    CS_URL_CN="https://gh-proxy.com/https://github.com/coder/code-server/releases/download/v${var.code_server_version}/code-server_${var.code_server_version}_amd64.deb"
    CS_URL_OFFICIAL="https://github.com/coder/code-server/releases/download/v${var.code_server_version}/code-server_${var.code_server_version}_amd64.deb"
    NODE_URL="https://npmmirror.com/mirrors/node/v${var.node_version}/node-v${var.node_version}-linux-x64.tar.xz"
    NODE_DIR="/usr/local/lib/nodejs/node-v${var.node_version}-linux-x64"
    NTFY_TOPIC="${var.ntfy_topic}"

    RESULT="ok"
    DETAIL=""
    CS_DEB="/root/cs.deb"
    NODE_TAR="/tmp/node.tar.xz"

    log() { echo "[bake $(date -u +%FT%TZ)] $*"; }

    # --- 1. 下载 code-server .deb：优先国内可达 GitHub 代理，失败回退官方地址 ---
    CS_OK=0
    for url in "$CS_URL_CN" "$CS_URL_OFFICIAL"; do
      for i in 1 2 3; do
        log "下载 code-server .deb：$url（第 $i/3 次）"
        if curl -fL --connect-timeout 15 --max-time 900 -C - -o "$CS_DEB" "$url"; then
          # 代理可能返回 200 但内容是错误页，用体积兜底校验
          if [ "$(stat -c%s "$CS_DEB" 2>/dev/null || echo 0)" -gt 100000000 ]; then
            CS_OK=1
            break 2
          fi
          log ".deb 体积异常（疑似代理错误页），重试"
        fi
        sleep 5
      done
    done

    if [ "$CS_OK" = "1" ]; then
      cd /root
      INSTALLED=0
      for i in 1 2; do
        apt-get update -y >/dev/null 2>&1 || true
        if apt-get install -y ./cs.deb >/dev/null 2>&1; then
          INSTALLED=1
          break
        fi
        dpkg -i ./cs.deb >/dev/null 2>&1 || true
        apt-get -f install -y >/dev/null 2>&1 || true
        if command -v code-server >/dev/null 2>&1; then
          INSTALLED=1
          break
        fi
        sleep 5
      done
      if [ "$INSTALLED" = "1" ]; then
        log "code-server 安装成功：$(code-server --version 2>/dev/null | head -n1)"
      else
        RESULT="fail"
        DETAIL="$DETAIL code-server 安装失败;"
      fi
    else
      RESULT="fail"
      DETAIL="$DETAIL code-server 下载失败;"
    fi

    # --- 2. Node.js：国内镜像下载官方二进制包，解压到 /usr/local（系统级可用） ---
    NODE_OK=0
    for i in 1 2 3; do
      log "下载 Node.js：$NODE_URL（第 $i/3 次）"
      if curl -fL --connect-timeout 15 --max-time 300 -o "$NODE_TAR" "$NODE_URL"; then
        NODE_OK=1
        break
      fi
      sleep 5
    done

    if [ "$NODE_OK" = "1" ]; then
      rm -rf /usr/local/lib/nodejs
      mkdir -p /usr/local/lib/nodejs
      if tar -xJf "$NODE_TAR" -C /usr/local/lib/nodejs; then
        for b in node npm npx; do
          ln -sf "$NODE_DIR/bin/$b" "/usr/local/bin/$b"
        done
        log "Node.js 就绪：$(node -v 2>/dev/null)"
      else
        RESULT="fail"
        DETAIL="$DETAIL node 解压失败;"
      fi
    else
      RESULT="fail"
      DETAIL="$DETAIL node 下载失败;"
    fi

    # --- 3. systemd 服务单元（root 运行、开机自启）---
    #     停用 deb 安装时自带的按用户实例（code-server@root/@ubuntu），
    #     避免其与下方自定义单元争夺 8080 端口
    systemctl disable --now code-server@root.service code-server@ubuntu.service >/dev/null 2>&1 || true

    cat > /etc/systemd/system/code-server.service <<'UNIT'
    [Unit]
    Description=code-server (browser VS Code)
    After=network.target

    [Service]
    Type=simple
    User=root
    WorkingDirectory=/root
    ExecStart=/usr/bin/code-server
    Restart=always
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    if ! systemctl enable code-server >/dev/null 2>&1; then
      RESULT="fail"
      DETAIL="$DETAIL systemd 服务启用失败;"
    fi

    # --- 4. 启动自检：本地请求 8080，确认登录页可响应 ---
    #     清除自动生成的配置，运行栈会写入正式的 bind-addr 与访问密码
    rm -rf /root/.config/code-server
    systemctl start code-server
    HTTP_CODE="000"
    for i in 1 2 3 4 5 6 7 8 9 10; do
      HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://127.0.0.1:8080/ || echo "000")
      case "$HTTP_CODE" in
        200|302|401|403) break ;;
      esac
      sleep 3
    done
    log "8080 自检 HTTP 状态码：$HTTP_CODE"

    CS_VERSION=$(code-server --version 2>/dev/null | head -n1 || echo "unknown")
    NODE_VERSION=$(node -v 2>/dev/null || echo "unknown")

    case "$HTTP_CODE" in
      200|302|401|403) ;;
      *)
        RESULT="fail"
        DETAIL="$DETAIL 8080 自检失败（HTTP $HTTP_CODE）;"
        ;;
    esac

    # --- 5. 收尾：停服务（保留开机自启），清理大文件与缓存，写完成标记 ---
    systemctl stop code-server
    # 清除自检期间自动生成的配置（含随机密码），避免镜像内残留旧配置；
    # 运行时由主栈写入正式配置并重启服务加载
    rm -rf /root/.config/code-server
    rm -f "$CS_DEB" "$NODE_TAR"
    apt-get clean >/dev/null 2>&1 || true
    rm -rf /root/.cache
    echo "$RESULT $DETAIL" > /root/.bake-result
    touch /root/.baked-vscode-image
    log "烘焙结束：$RESULT $DETAIL"

    # --- 6. 可选：向 ntfy.sh 主题推送烘焙结果（不含任何敏感信息） ---
    if [ -n "$NTFY_TOPIC" ]; then
      curl -s -m 20 -d "{\"status\":\"$RESULT\",\"detail\":\"$DETAIL\",\"code_server\":\"$CS_VERSION\",\"node\":\"$NODE_VERSION\",\"http_8080\":\"$HTTP_CODE\"}" "https://ntfy.sh/$NTFY_TOPIC" || true
    fi
  EOT

  tags = {
    project = var.project_name
    role    = "image-builder"
  }
}

resource "huaweicloud_vpc_eip_associate" "bake" {
  public_ip = huaweicloud_vpc_eip.bake.address
  port_id   = huaweicloud_compute_instance.builder.network[0].port
}

# ---------------------------------------------------------------------------
# 私有镜像：烘焙确认完成后，将 create_image 置为 true 再 apply 一次
# ---------------------------------------------------------------------------

resource "huaweicloud_ims_ecs_system_image" "baked" {
  count = var.create_image ? 1 : 0

  name        = "${var.project_name}-image-cs${replace(var.code_server_version, ".", "_")}-node${replace(var.node_version, ".", "_")}"
  instance_id = huaweicloud_compute_instance.builder.id
  description = "预装 code-server v${var.code_server_version} 与 Node.js v${var.node_version} 的系统盘私有镜像"

  timeouts {
    create = "40m"
  }
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

output "builder_instance_id" {
  description = "构建实例 ID（排查烘焙问题时使用）"
  value       = huaweicloud_compute_instance.builder.id
}

output "builder_eip" {
  description = "构建实例弹性公网 IP"
  value       = huaweicloud_vpc_eip.bake.address
}

output "image_id" {
  description = "烘焙产出的私有镜像 ID（供 infra/ 主栈 private_image_id 引用）"
  value       = try(huaweicloud_ims_ecs_system_image.baked[0].id, "")
}

output "image_name" {
  description = "烘焙产出的私有镜像名称"
  value       = try(huaweicloud_ims_ecs_system_image.baked[0].name, "")
}
