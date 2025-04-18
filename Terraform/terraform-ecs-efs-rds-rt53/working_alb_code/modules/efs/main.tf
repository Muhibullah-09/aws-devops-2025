resource "aws_efs_file_system" "wordpress" {
  creation_token = "wordpress-efs"
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.sg_efs_id]
}

resource "aws_efs_access_point" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id
  posix_user {
    uid = 1000
    gid = 1000
  }
  root_directory {
    path = "/wordpress"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }
  tags = {
    Name = "wordpress-access-point"
  }
}

output "efs_file_system_id" {
  value = aws_efs_file_system.wordpress.id
}

output "efs_access_point_id" {
  value = aws_efs_access_point.wordpress.id  # This matches the variable name
}