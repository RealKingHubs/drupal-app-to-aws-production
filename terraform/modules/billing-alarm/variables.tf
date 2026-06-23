variable "project"          { type = string }
variable "environment"      { type = string }
variable "alert_email"      { type = string }
variable "budget_limit_usd" {
  type        = number
  default     = 50
  description = "Total project budget in USD - alarms fire at 50% and 90% of this"
}
