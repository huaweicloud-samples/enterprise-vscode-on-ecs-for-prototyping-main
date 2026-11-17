variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "资源命名前缀"
  type        = string
  default     = "browser-vscode-dev-env"
}

variable "availability_zone" {
  description = "可用区完整名称，如 cn-north-4a"
  type        = string
  default     = "cn-north-4a"
}

variable "flavor_id" {
  description = "弹性云服务器规格（2 核 4 GB，匹配常见开发机算力）"
  type        = string
  default     = "s6.large.2"
}

variable "image_name_regex" {
  description = "公共镜像名称正则（首尾锚定，避免命中带 GPU 驱动变体）"
  type        = string
  default     = "^Ubuntu 22.04 server 64bit$"
}

variable "volume_size" {
  description = "系统盘容量（GiB），默认 128"
  type        = number
  default     = 128
}

variable "system_disk_type" {
  description = "系统盘类型（必填显式决策，非 provider 默认值）"
  type        = string
  default     = "GPSSD"
}

variable "bandwidth_size" {
  description = "弹性公网 IP 带宽大小（Mbit/s）"
  type        = number
  default     = 5
}

variable "allowed_cidr" {
  description = "允许访问 8080 端口的源 IP 段；部署前请改为本机公网 IP 或办公网段"
  type        = string
  default     = "0.0.0.0/0"
}

variable "vscode_password" {
  description = "浏览器版 VS Code 访问密码（至少 12 位，请勿使用弱口令）"
  type        = string
  sensitive   = true
}

variable "private_image_id" {
  description = "预置私有镜像 ID（由 infra/image-bake 烘焙产出）；留空则使用公共镜像并在开机时自动安装"
  type        = string
  default     = ""
}

variable "healthcheck_topic" {
  description = "可选：部署后向该 ntfy.sh 主题推送健康检查结果（HTTP 状态码与软件版本，不含敏感信息）；留空则不推送"
  type        = string
  default     = ""
}
