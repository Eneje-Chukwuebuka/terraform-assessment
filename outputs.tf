output "bastion_host_ip" {
  description = "The ip address to the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "web_server_ip" {
  description = "The ip address to the web server"
  value       = [for instance in aws_instance.web : instance.private_ip]
}

output "db_server_ip" {
  description = "The ip address to the db server"
  value       = aws_instance.db.private_ip
}

output "vpc_id" {
  description = "The id of this vpc we created in aws"
  value       = aws_vpc.this.id
}

output "lb_dns" {
  description = " the name of the application load balancer dns name"
  value       = aws_lb.this.dns_name
}
