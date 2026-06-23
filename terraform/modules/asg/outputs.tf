output "autoscaling_group_name" {
   value = aws_autoscaling_group.app.name 
   }

output "autoscaling_group_arn"  { 
  value = aws_autoscaling_group.app.arn
   }

output "launch_template_id"     { 
  value = aws_launch_template.app.id
   }

