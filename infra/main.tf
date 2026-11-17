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

locals {
  # 镜像选择：预置私有镜像（infra/image-bake 烘焙产出）优先；
  # 未提供 private_image_id 时回退公共 Ubuntu 镜像，由开机脚本自动安装。
  image_id = var.private_image_id != "" ? var.private_image_id : data.huaweicloud_images_image.ubuntu[0].id
}

# ---------------------------------------------------------------------------
# 网络：私有网络、子网、安全组
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc" "main" {
  name                  = "${var.project_name}-vpc"
  cidr                  = "10.0.0.0/16"
  enterprise_project_id = null
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "安全组：仅开放浏览器开发环境所需端口"
}

# 入方向仅开放浏览器版 VS Code 端口，来源受 allowed_cidr 约束
resource "huaweicloud_networking_secgroup_rule" "allow_vscode" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = var.allowed_cidr
  security_group_id = huaweicloud_networking_secgroup.main.id
}

# ---------------------------------------------------------------------------
# 公网入口：弹性公网 IP（实例借其出网，并对外提供浏览器访问）
# ---------------------------------------------------------------------------

resource "huaweicloud_vpc_eip" "main" {
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

# ---------------------------------------------------------------------------
# 计算实例：运行浏览器版 VS Code 的弹性云服务器
# ---------------------------------------------------------------------------

data "huaweicloud_images_image" "ubuntu" {
  count        = var.private_image_id == "" ? 1 : 0
  name_regex   = var.image_name_regex
  most_recent  = true
}

resource "huaweicloud_compute_instance" "dev" {
  name              = "${var.project_name}-ecs"
  flavor_id         = var.flavor_id
  availability_zone = var.availability_zone
  image_id          = local.image_id

  security_group_ids = [huaweicloud_networking_secgroup.main.id]

  # 系统盘：类型与容量均显式决策
  system_disk_type = var.system_disk_type
  system_disk_size = var.volume_size

  network {
    uuid = huaweicloud_vpc_subnet.main.id
  }

  # 实例启动后写入配置并拉起浏览器版 VS Code。两种镜像路径：
  #   a) private_image_id 为空：使用公共 Ubuntu 镜像，开机自动安装
  #      code-server 与 Node.js（安装均带重试与超时，Node.js 走国内镜像）；
  #   b) private_image_id 已设置（infra/image-bake 烘焙产出）：软件随镜像就绪，
  #      开机跳过安装，仅写入配置并启动服务，分钟级可用。
  # 说明：华为云 Ubuntu 镜像默认用户为 root（无 ubuntu 用户），故全程以 root 运行。
  user_data = <<-EOT
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive

    # 可选健康检查通知主题（由 Terraform 渲染为字面量；为空则跳过推送）
    HEALTHCHECK_TOPIC="${var.healthcheck_topic}"

    # 等待云初始化网络就绪，避免开机瞬间外网尚未可用
    sleep 10

    # 若使用了预置私有镜像，code-server 与 Node.js 已随镜像安装，跳过安装步骤
    if ! command -v code-server >/dev/null 2>&1; then
      # 安装浏览器版 VS Code（code-server）：先下载后执行，带重试与超时
      CS_INSTALLED=0
      for i in 1 2 3 4 5; do
        if curl -fsSL --connect-timeout 15 --max-time 180 -o /tmp/cs-install.sh https://code-server.dev/install.sh && [ -s /tmp/cs-install.sh ] && timeout 300 sh /tmp/cs-install.sh; then
          CS_INSTALLED=1
          break
        fi
        sleep 5
      done
    fi

    if ! command -v node >/dev/null 2>&1; then
      # 安装 Node.js 20.11.0（nvm，root）：带重试与超时，并使用国内镜像加速
      export NVM_DIR="/root/.nvm"
      if ! command -v git >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y git || true
      fi
      NODE_INSTALLED=0
      for i in 1 2 3 4 5; do
        if curl -fsSL --connect-timeout 15 --max-time 120 -o /tmp/nvm-install.sh https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh && [ -s /tmp/nvm-install.sh ] && timeout 120 bash /tmp/nvm-install.sh; then
          export NVM_DIR="$HOME/.nvm"
          [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || true
          export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"
          if timeout 300 nvm install 20.11.0; then
            nvm alias default 20.11.0 >/dev/null 2>&1 || true
            NODE_INSTALLED=1
            break
          fi
        fi
        sleep 5
      done
    fi

    # 配置浏览器版 VS Code 监听地址与访问密码（root）
    mkdir -p /root/.config/code-server
    cat > /root/.config/code-server/config.yaml <<CFG
    bind-addr: 0.0.0.0:8080
    auth: password
    password: ${var.vscode_password}
    cert: false
    CFG

    # 停用安装脚本可能自启的 code-server@<user> 实例，避免与下方自定义服务端口冲突
    systemctl disable --now code-server@root.service code-server@ubuntu.service 2>/dev/null || true

    # 以 systemd 服务形式启动（root，含开机自启）
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
    systemctl enable code-server
    # 必须重启而非仅启动：预置私有镜像中该单元开机自启，开机时可能已用镜像内
    # 旧配置（随机密码、仅回环监听）先行启动；restart 确保加载刚写入的配置，
    # 使服务监听 0.0.0.0 且访问密码生效。
    systemctl restart code-server

    # 可选：部署后健康检查结果推送（便于无公网直连环境确认服务状态；不含敏感信息）
    # 含实例内模拟登录自检：从本地配置读取密码并完成一次登录，
    # 验证密码认证链路可用；密码本身不离开实例。
    if [ -n "$HEALTHCHECK_TOPIC" ]; then
      HEALTH_CODE="000"
      for i in 1 2 3 4 5; do
        HEALTH_CODE=$(curl -s -o /dev/null -w "%%{http_code}" http://127.0.0.1:8080/ || echo "000")
        case "$HEALTH_CODE" in 200|302|401|403) break ;; esac
        sleep 2
      done
      HEALTH_CS=$(code-server --version 2>/dev/null | head -n1 || echo "unknown")
      HEALTH_NODE=$(node -v 2>/dev/null || echo "unknown")
      # 经私网 IP 访问：验证服务监听在所有网卡（0.0.0.0），而非仅回环地址
      HEALTH_BIND="unknown"
      HEALTH_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
      if [ -n "$HEALTH_IP" ]; then
        HEALTH_BIND=$(curl -s -o /dev/null -w "%%{http_code}" http://$HEALTH_IP:8080/ || echo "000")
      fi
      HEALTH_LOGIN="skipped"
      HEALTH_PW=$(grep '^password:' /root/.config/code-server/config.yaml 2>/dev/null | awk '{print $2}')
      if [ -n "$HEALTH_PW" ]; then
        LOGIN_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -c /tmp/health-cookie -d "password=$HEALTH_PW" http://127.0.0.1:8080/login || echo "000")
        HOME_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -b /tmp/health-cookie http://127.0.0.1:8080/ || echo "000")
        if [ "$HOME_CODE" = "200" ]; then
          HEALTH_LOGIN="ok(login:$LOGIN_CODE,home:$HOME_CODE)"
        else
          HEALTH_LOGIN="fail(login:$LOGIN_CODE,home:$HOME_CODE)"
        fi
        rm -f /tmp/health-cookie
      fi
      curl -s -m 20 -d "{\"http_8080\":\"$HEALTH_CODE\",\"bind_via_private_ip\":\"$HEALTH_BIND\",\"login\":\"$HEALTH_LOGIN\",\"code_server\":\"$HEALTH_CS\",\"node\":\"$HEALTH_NODE\"}" "https://ntfy.sh/$HEALTHCHECK_TOPIC" || true
    fi
  EOT

  tags = {
    project = var.project_name
  }
}

resource "huaweicloud_vpc_eip_associate" "main" {
  public_ip = huaweicloud_vpc_eip.main.address
  port_id   = huaweicloud_compute_instance.dev.network[0].port
}
