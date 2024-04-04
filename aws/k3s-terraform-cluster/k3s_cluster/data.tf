data "aws_caller_identity" "current" {}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

data "aws_ssm_parameter" "remote_state_bucket" {
  name            = "/tf/${var.global_config.name}/${var.global_config.environment}/tfBucketName"
  with_decryption = true
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = data.aws_ssm_parameter.remote_state_bucket.value
    key    = "${var.global_config.name}-network-services.tfstate"
    region = var.global_config.region
  }
}

resource "random_password" "k3s_token" {
  length  = 55
  special = false
}

data "aws_iam_policy" "AmazonEC2ReadOnlyAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_instances" "k3s_servers" {

  depends_on = [
    aws_autoscaling_group.k3s_servers_asg,
  ]

  instance_tags = {
    k3s-instance-type = "k3s-server"
    provisioner       = "terraform"
    environment       = var.global_config.environment
  }

  instance_state_names = ["running"]
}

data "aws_instances" "k3s_workers" {

  depends_on = [
    aws_autoscaling_group.k3s_workers_asg,
  ]

  instance_tags = {
    k3s-instance-type = "k3s-worker"
    provisioner       = "terraform"
    environment       = var.global_config.environment
  }

  instance_state_names = ["running"]
}

data "template_cloudinit_config" "k3s_server" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/files/cloud-config-base.yaml", {})
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/files/k3s-install-server.sh", {
      k3s_version                      = var.k3s_version,
      k3s_token                        = random_password.k3s_token.result,
      k3s_subnet                       = var.k3s_subnet,
      is_k3s_server                    = true,
      install_node_termination_handler = var.install_node_termination_handler,
      node_termination_handler_release = var.node_termination_handler_release,
      install_nginx_ingress            = var.install_nginx_ingress,
      nginx_ingress_release            = var.nginx_ingress_release,
      install_certmanager              = var.install_certmanager,
      efs_persistent_storage           = var.cluster_config.efs_persistent_storage,
      efs_csi_driver_release           = var.efs_csi_driver_release,
      efs_filesystem_id                = var.cluster_config.efs_persistent_storage ? aws_efs_file_system.k3s_persistent_storage[0].id : "",
      certmanager_release              = var.certmanager_release,
      certmanager_email_address        = var.certmanager_email_address,
      expose_kubeapi                   = var.cluster_config.expose_kubeapi,
      k3s_tls_san_public               = local.k3s_tls_san_public,
      k3s_url                          = aws_lb.k3s_server_lb.dns_name,
      k3s_tls_san                      = aws_lb.k3s_server_lb.dns_name,
      kubeconfig_secret_name           = local.kubeconfig_secret_name
      environment                      = var.global_config.environment
    })
  }
}

data "template_cloudinit_config" "k3s_worker" {
  gzip          = true
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/files/cloud-config-base.yaml", {})
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/files/k3s-install-worker.sh", {
      k3s_version   = var.k3s_version,
      k3s_token     = random_password.k3s_token.result,
      k3s_subnet    = var.k3s_subnet,
      is_k3s_server = false,
      k3s_url       = aws_lb.k3s_server_lb.dns_name,
      k3s_tls_san   = aws_lb.k3s_server_lb.dns_name
    })
  }
}