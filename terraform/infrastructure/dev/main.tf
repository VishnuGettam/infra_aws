resource "aws_instance" "WebServer" {
  ami           = data.aws_ami.amazon_linux_dev.id
  instance_type = var.instance_type

  user_data = file(var.webserver_userdata)
  key_name  = var.ssh_key


  tags = {
    Name = var.instance_name
  }

}