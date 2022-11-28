variable "environment_tag" {
  description = "Environment"
  default     = "dev"
}

variable "ecs_name" {
  description = "Name primitive to use for all resources created"
  type        = string
  default     = "EcsService"
}

variable "repository_name" {
  description = "Value of the Name tag for the Auth ECR Repository"
  type        = string
  default     = "CodeRepository"
}

variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/24"
}

variable "cidr_subnet1" {
  description = "CIDR block for the subnet"
  default     = "10.0.0.0/25"
}

variable "cidr_subnet2" {
  description = "CIDR block for the subnet"
  default     = "10.0.0.128/25"
}

# Fargate
variable "fargate_cpu" {
  description = "CPU size for fargate"
  default     = 1024
  type        = number
}
variable "fargate_mem" {
  description = "Memory to use for fargate"
  default     = 2048
  type        = number
}

# Builder container
variable "container_cpu" {
  description = "CPU to use for container, must be equal or less than fargate"
  default     = 1024
  type        = number
}
variable "container_mem" {
  description = "Memory to use for container, must be equal or less than fargate"
  default     = 2048
  type        = number
}

variable "image_tag" {
  description = "Tag to use when pulling ECR image"
  default     = "latest"
  type        = string
}