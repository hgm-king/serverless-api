provider "aws" {
  region = "us-east-2"
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet_public1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.cidr_subnet1
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-2a"
}

resource "aws_subnet" "subnet_public2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.cidr_subnet2
  map_public_ip_on_launch = "true"
  availability_zone       = "us-east-2b"
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta_subnet_public1" {
  subnet_id      = aws_subnet.subnet_public1.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_route_table_association" "rta_subnet_public2" {
  subnet_id      = aws_subnet.subnet_public2.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_ecr_repository" "repository" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# Cluster is compute that service will run on
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "Cluster"
  capacity_providers = [
    "FARGATE"
  ]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
  }
}

# Cloudwatch to store logs
resource "aws_cloudwatch_log_group" "AuthCloudWatchLogGroup" {
  name = "${var.ecs_name}LogGroup"
}


# Create new IAM role for execution policy to use
resource "aws_iam_role" "AuthExecutionRole" {
  name = "${var.ecs_name}ExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

# Link to AWS-managed policy - AmazonECSTaskExecutionRolePolicy
resource "aws_iam_role_policy_attachment" "AuthExecutionRole_to_ecsTaskExecutionRole" {
  role       = aws_iam_role.AuthExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "AuthExecutionRole_to_CognitoExecutionRole" {
  role       = aws_iam_role.AuthExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonESCognitoAccess"
}

# Task definition
# Will be relaunched by service frequently
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                   = var.ecs_name
  execution_role_arn       = aws_iam_role.AuthExecutionRole.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_mem
  container_definitions = jsonencode(
    [
      {
        name      = "${var.ecs_name}"
        image     = "${aws_ecr_repository.repository.repository_url}:${var.image_tag}"
        cpu       = "${var.container_cpu}"
        memory    = "${var.container_mem}"
        essential = true
        environment = [
          { name : "PORT", value : "80" },
        ]
        logConfiguration : {
          logDriver : "awslogs",
          options : {
            awslogs-group : "${var.ecs_name}LogGroup",
            awslogs-region : "${data.aws_region.current_region.name}",
            awslogs-stream-prefix : "${var.ecs_name}"
          }
        }
        portMappings = [
          {
            containerPort = 80
            hostPort      = 80
          }
        ]
      }
    ]
  )
}


# Load Balanacers
resource "aws_lb" "load_balancer" {
  name               = "${var.ecs_name}LB"
  internal           = false
  load_balancer_type = "application"
  security_groups = [ # A list of SGs to assign to the container
    aws_security_group.allow_http.id,
  ]
  subnets = [ # A list of subnets to put the fargate and container into
    aws_subnet.subnet_public1.id,
    aws_subnet.subnet_public2.id,
  ]
  enable_deletion_protection = false
}


resource "aws_lb_target_group" "load_balancer_group" {
  name        = "${var.ecs_name}LBGroup"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"
  health_check {
    path = "/health"
  }
}

resource "aws_lb_listener" "lb_listener_http" {
  load_balancer_arn = aws_lb.load_balancer.id
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.load_balancer_group.id
    type             = "forward"
  }
}


# Service definition, auto heals if task shuts down
resource "aws_ecs_service" "ecs_service" {
  name             = "${var.ecs_name}Service"
  cluster          = aws_ecs_cluster.fargate_cluster.id
  task_definition  = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"
  network_configuration {
    security_groups = [ # A list of SGs to assign to the container
      aws_security_group.allow_http.id,
    ]
    subnets = [ # A list of subnets to put the fargate and container into
      aws_subnet.subnet_public1.id,
      aws_subnet.subnet_public2.id,
    ]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.load_balancer_group.arn
    container_name   = var.ecs_name
    container_port   = 80
  }

  # Ignored desired count changes live, permitting schedulers to update this value without terraform reverting
  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "OstrichApi"
}

resource "aws_api_gateway_resource" "resource" {
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "auth"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}


resource "aws_api_gateway_resource" "proxy_resource" {
  parent_id   = aws_api_gateway_resource.resource.id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}


resource "aws_api_gateway_method" "any_method" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "any_http_handler" {
  http_method             = aws_api_gateway_method.any_method.http_method
  integration_http_method = aws_api_gateway_method.any_method.http_method
  resource_id             = aws_api_gateway_resource.proxy_resource.id
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  type                    = "HTTP_PROXY"
  connection_type         = "INTERNET"
  uri                     = "http://${aws_lb.load_balancer.dns_name}/{proxy}"
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}


resource "aws_api_gateway_method" "option_method" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.proxy_resource.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "option_http_handler" {
  http_method = aws_api_gateway_method.option_method.http_method
  resource_id = aws_api_gateway_resource.proxy_resource.id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  type        = "MOCK"
  request_templates = {
    "application/json" = <<EOF
{"statusCode": 200}
EOF
  }
}

resource "aws_api_gateway_integration_response" "option_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.proxy_resource.id
  http_method = aws_api_gateway_method.option_method.http_method
  status_code = 200

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'",
    "method.response.header.Access-Control-Allow-Origin" = "'*'",
  }
}

resource "aws_api_gateway_method_response" "option_method_response" {
  rest_api_id = "${aws_api_gateway_rest_api.api_gateway.id}"
  resource_id = "${aws_api_gateway_resource.proxy_resource.id}"
  http_method = "${aws_api_gateway_method.option_method.http_method}"
  status_code = 200
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.resource.id,
      aws_api_gateway_resource.proxy_resource.id,
      aws_api_gateway_method.any_method.id,
      aws_api_gateway_method.option_method.id,
      aws_api_gateway_integration.any_http_handler.id,
      aws_api_gateway_integration.option_http_handler.id,
      aws_api_gateway_integration_response.option_integration_response.id,
      aws_api_gateway_method_response.option_method_response.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1_api_gateway_stage" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "v1"
}