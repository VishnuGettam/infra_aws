variable "aws_region" {
  description = "aws region"
  type        = string
}

variable "instance_type" {
  description = "ec2 instance type"
  type        = string
}

variable "instance_name" {
  description = "ec2 instance name"
  type        = string
}

variable "ssh_key" {
  description = "SSH key for WebServer"
  type        = string
}

variable "webserver_userdata" {
  description = "User data for webserver"
  type        = string
}