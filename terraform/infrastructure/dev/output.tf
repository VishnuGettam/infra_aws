output "WebServer_PublicIP" {
  description = "Public Ip of the WebServer"
  value       = aws_instance.WebServer.public_ip
}

output "Instance_ID" {
  value = aws_instance.WebServer.id
}