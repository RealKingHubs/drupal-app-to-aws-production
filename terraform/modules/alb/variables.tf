variable "project"            { type = string }
variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "public_subnet_ids"  { type = list(string) }
variable "alb_security_group" { type = string }
variable "certificate_arn"    { type = string }
