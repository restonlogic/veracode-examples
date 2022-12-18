resource "aws_lb" "k3s_server_lb" {
  name               = "${var.common_prefix}-int-lb-${var.global_config.environment}"
  load_balancer_type = "network"
  internal           = "true"
  subnets            = data.terraform_remote_state.vpc.outputs.public_subnets

  enable_cross_zone_load_balancing = true

  tags = merge(
    local.global_tags,
    {
      "Name" = lower("${var.common_prefix}-int-lb-${var.global_config.environment}")
    }
  )
}

resource "aws_lb_listener" "k3s_server_listener" {
  load_balancer_arn = aws_lb.k3s_server_lb.arn

  protocol = "TCP"
  port     = var.kube_api_port

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_server_tg.arn
  }

  tags = merge(
    local.global_tags,
    {
      "Name" = lower("${var.common_prefix}-kubeapi-listener-${var.global_config.environment}")
    }
  )
}

resource "aws_lb_target_group" "k3s_server_tg" {
  port     = var.kube_api_port
  protocol = "TCP"
  vpc_id   = data.terraform_remote_state.vpc.outputs.vpc_id


  depends_on = [
    aws_lb.k3s_server_lb
  ]

  health_check {
    protocol = "TCP"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    local.global_tags,
    {
      "Name" = lower("${var.common_prefix}-internal-lb-tg-kubeapi-${var.global_config.environment}")
    }
  )
}

resource "aws_autoscaling_attachment" "k3s_server_target_kubeapi" {

  depends_on = [
    aws_autoscaling_group.k3s_servers_asg,
    aws_lb_target_group.k3s_server_tg
  ]

  autoscaling_group_name = aws_autoscaling_group.k3s_servers_asg.name
  lb_target_group_arn    = aws_lb_target_group.k3s_server_tg.arn
}