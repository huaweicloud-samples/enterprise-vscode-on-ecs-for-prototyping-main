# ============================================================================
# 输出：部署后可直接用于访问的关键信息
# ============================================================================

output "ecs_instance_id" {
  description = "运行浏览器版 VS Code 的弹性云服务器实例 ID"
  value       = huaweicloud_compute_instance.dev.id
}

output "ecs_instance_name" {
  description = "弹性云服务器实例名称"
  value       = huaweicloud_compute_instance.dev.name
}

output "eip_public_ip" {
  description = "弹性公网 IP 地址（浏览器访问入口）"
  value       = huaweicloud_vpc_eip.main.address
}

output "vscode_access_url" {
  description = "浏览器版 VS Code 访问地址（部署成功后复制到浏览器打开）"
  value       = "http://${huaweicloud_vpc_eip.main.address}:8080"
}

output "vscode_port" {
  description = "浏览器版 VS Code 监听端口"
  value       = 8080
}

output "used_image_id" {
  description = "实例实际使用的镜像 ID（预置私有镜像或公共 Ubuntu 镜像）"
  value       = local.image_id
}
