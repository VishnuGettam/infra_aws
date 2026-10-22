output "WebServer_PublicIP" {
  description = "Public Ip of the WebServer"
  value       = aws_instance.WebServer.public_ip
}

output "Instance_ID" {
  value = aws_instance.WebServer.id
}

output "WebServer_AZ" {
  value = aws_instance.WebServer.availability_zone
}

output "WebServer_Ec2DNS" {
  value = aws_instance.WebServer.public_dns
}