resource "aws_iam_role" "task_execution_role" {
  name = "ecsTaskExecutionRole"
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

# Attach the default ECS task execution policy (covers ECR and CloudWatch)
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Add policy for Secrets Manager access (for RDS credentials)
resource "aws_iam_policy" "secrets_access" {
  name        = "ecs-secrets-access"
  description = "Allow ECS tasks to access Secrets Manager"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*" # Ideally, specify the exact secret ARN
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_access_attachment" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

# Define the task role (moved from ecs/main.tf)
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

# Add policy for EFS access (moved from ecs/main.tf)
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
        Resource = "*" # Ideally, specify the exact EFS ARN
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

# Outputs for task execution role
output "task_execution_role_arn" {
  value = aws_iam_role.task_execution_role.arn
}

output "task_execution_role_name" {
  value = aws_iam_role.task_execution_role.name
}

# Output for task role (to be used in ecs module)
output "task_role_arn" {
  value = aws_iam_role.task_role.arn
}
