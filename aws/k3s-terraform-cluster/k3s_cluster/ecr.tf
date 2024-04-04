module "ecr" {
  #count  = var.global_config.environment == "mgmt" ? 1 : 0
  source = "../modules/ecr"

  global_config = var.global_config
  microservices = var.microservices
}