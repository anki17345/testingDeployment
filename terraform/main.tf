provider "aws" {
  region = "us-west-1"
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.10.0"

  name = "openpolitica-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-1a", "us-west-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform   = "true"
    Project     = "OpenPolitica"
    Environment = "dev"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "openpolitica-cluster"
  tags = {
    Project = "OpenPolitica"
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "openpolitica-ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = {
    Project = "OpenPolitica"
  }
}

# Attach policies to the role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Security Group for ECS
resource "aws_security_group" "ecs" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "ecs-sg"
    Project = "OpenPolitica"
  }
}

# RDS PostgreSQL
resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "13.3"
  instance_class       = "db.t3.micro"
  name                 = "mydatabase"
  username             = "dbuser"
  password             = "dbpassword"
  parameter_group_name = "default.postgres13"
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.rds.name

  tags = {
    Name    = "mydatabase"
    Project = "OpenPolitica"
  }
}

# RDS Security Group
resource "aws_security_group" "rds" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "rds-sg"
    Project = "OpenPolitica"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds" {
  name       = "rds-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name    = "rds-subnet-group"
    Project = "OpenPolitica"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "django" {
  family                   = "django-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = "django"
      image = "925206540702.dkr.ecr.us-west-1.amazonaws.com/testing-deploy:production" # Replace with your Docker image
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
        }
      ]
      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.postgres.address
        },
        {
          name  = "DB_PORT"
          value = "5432"
        },
        {
          name  = "DB_NAME"
          value = aws_db_instance.postgres.name
        },
        {
          name  = "DB_USER"
          value = aws_db_instance.postgres.username
        },
        {
          name  = "DB_PASSWORD"
          value = aws_db_instance.postgres.password
        },
        {
          name  = "DJANGO_SETTINGS_MODULE"
          value = "core.settings"
        }
      ]
    }
  ])

  tags = {
    Project = "OpenPolitica"
  }
}

# ECS Service
resource "aws_ecs_service" "django" {
  name            = "django-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.django.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.public_subnets
    security_groups = [aws_security_group.ecs.id]
  }

  desired_count = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.django.arn
    container_name   = "django"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.frontend]

  tags = {
    Project = "OpenPolitica"
  }
}

# Application Load Balancer
resource "aws_lb" "app" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name    = "app-lb"
    Project = "OpenPolitica"
  }
}

resource "aws_lb_target_group" "django" {
  name     = "django-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name    = "django-tg"
    Project = "OpenPolitica"
  }
}

resource "aws_lb_listener" "frontend" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.django.arn
  }
}