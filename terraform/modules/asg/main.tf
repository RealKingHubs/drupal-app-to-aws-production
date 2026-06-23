# ============================================================
# ASG Module
# Auto Scaling Group running t2.micro Drupal app servers
# CAPPED at max_size = 4 so it can never run away on cost.
# desired = 2 keeps us inside the 750 free hours/month pool.
# ============================================================

# ============================================================
# IAM Role for EC2 instances
# SSM access (no need to open SSH to the world), S3 access,
# CloudWatch agent access for metrics
# ============================================================
resource "aws_iam_role" "app" {
  name = "${var.project}-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3_drupal_files" {
  name = "${var.project}-${var.environment}-s3-drupal"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.s3_bucket_name}",
        "arn:aws:s3:::${var.s3_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-${var.environment}-app-profile"
  role = aws_iam_role.app.name
}

# ============================================================
# Launch Template
# ============================================================
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-app-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [var.app_security_group]

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = 8  # Free tier covers up to 30GB total EBS, keep this lean
      delete_on_termination = true
      encrypted             = true
    }
  }

  monitoring {
    enabled = false # Detailed monitoring costs extra - basic 5-min monitoring is free
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    db_host        = var.db_host
    db_name        = var.db_name
    db_username    = var.db_username
    db_password    = var.db_password
    s3_bucket_name = var.s3_bucket_name
    region         = "us-east-1"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project}-${var.environment}-app"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# Auto Scaling Group
# min=2 desired=2 max=4 - HARD CAP to control cost
# Spread across both private subnets (both AZs)
# ============================================================
resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-${var.environment}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [var.alb_target_group_arn]
  health_check_type   = "ELB"

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-app"
    propagate_at_launch = true
  }
}

# ============================================================
# Scaling Policies
# Threshold set HIGH (80%) so it only scales under real load,
# not noise. Scale-in is fast so we drop back to 2 quickly
# and stay inside free tier.
# ============================================================
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project}-${var.environment}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.project}-${var.environment}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 180
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80 # High threshold - only scale on genuine sustained load
  alarm_description   = "Scale out only when CPU stays above 80% for 4 minutes straight"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project}-${var.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Scale in quickly when CPU drops below 20% to stay within free tier"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}
