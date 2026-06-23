variable "project"       { type = string }
variable "environment"   { type = string }
variable "vpc_id"        { type = string }
variable "vpc_cidr"      { type = string }
variable "admin_ip_cidr" {
  type        = string
  description = "Your IP in CIDR format e.g. 1.2.3.4/32, used for SSH and metrics access"
}
