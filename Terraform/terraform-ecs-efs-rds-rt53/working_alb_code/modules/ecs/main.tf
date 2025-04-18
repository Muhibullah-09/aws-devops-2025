resource "aws_ecs_cluster" "wordpress" {
  name = "wordpress-cluster"
}

resource "aws_cloudwatch_log_group" "wordpress" {
  name = "/ecs/wordpress"
}

resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "wordpress" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name  = "wordpress"
    image = "wordpress:latest"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
    environment = [{
      name  = "WORDPRESS_DB_HOST"
      value = var.rds_cluster_endpoint
      }, {
      name  = "WORDPRESS_DB_NAME"
      value = "wordpress"
    }]
    secrets = [{
      name      = "WORDPRESS_DB_USER"
      valueFrom = "${var.secret_arn}:username::"
      }, {
      name      = "WORDPRESS_DB_PASSWORD"
      valueFrom = "${var.secret_arn}:password::"
    }]
    mountPoints = [{
      sourceVolume  = "wordpress-efs"
      containerPath = "/var/www/html"
      readOnly      = false
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.wordpress.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  volume {
    name = "wordpress-efs"
    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.efs_access_point_id # Move access_point to authorization_config
        iam             = "ENABLED"
      }
    }
  }
}

resource "aws_iam_role" "task_role" {
  name = "ecsTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "efs_access" {
  name        = "ecs-efs-access"
  description = "Allow ECS tasks to access EFS"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = "arn:aws:elasticfilesystem:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/${var.efs_file_system_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeFileSystems"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_access_attachment" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.efs_access.arn
}

resource "aws_iam_policy" "secrets_access" {
  name        = "ecs-secrets-access"
  description = "Allow ECS tasks to access Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access_attachment" {
  role       = var.task_execution_role_name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.wordpress.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress.arn
    container_name   = "wordpress"
    container_port   = 80
  }
}

data "aws_caller_identity" "current" {}

output "alb_dns_name" {
  value = aws_lb.wordpress.dns_name
}
