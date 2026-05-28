provider "aws" {
  region = "ap-southeast-2" # Khu vực Sydney như yêu cầu
}

data "aws_caller_identity" "current" {}

# ==========================================
# 1. NETWORKING (VPC Public Only)
# ==========================================
resource "aws_vpc" "audit_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "Audit-VPC-Sydney"
  }
}

resource "aws_subnet" "public_subnet_sydney" {
  vpc_id                  = aws_vpc.audit_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "Audit-Public-Subnet-Sydney"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.audit_vpc.id
  tags = {
    Name = "Audit-VPC-IGW-Sydney"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.audit_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "Audit-Public-RouteTable-Sydney"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet_sydney.id
  route_table_id = aws_route_table.public_rt.id
}

# ==========================================
# 2. STORAGE (S3 Evidence Bucket)
# ==========================================
resource "aws_s3_bucket" "evidence_bucket" {
  bucket        = "aws-security-audit-evidence-sydney-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = {
    Name = "Audit-Evidence-Bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket                  = aws_s3_bucket.evidence_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# 3. IAM ROLE & POLICIES (Đã sửa lỗi Statement chữ hoa)
# ==========================================
resource "aws_iam_role" "agent_execution_role" {
  name = "Sydney-Bedrock-Audit-Agent-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockToAssume"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowLocalAccountToAssume"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })
}

# Gắn policy chuyên dụng SecurityAudit của AWS (Cung cấp quyền Read-Only để kiểm toán mọi dịch vụ)
resource "aws_iam_role_policy_attachment" "security_audit_attach" {
  role       = aws_iam_role.agent_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

# Custom Policy cấp quyền tương tác S3 và gọi tài nguyên Bedrock Browser Tool
resource "aws_iam_role_policy" "agent_custom_policy" {
  name = "Sydney-Bedrock-Audit-Custom-Policy"
  role = aws_iam_role.agent_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.evidence_bucket.arn,
          "${aws_s3_bucket.evidence_bucket.arn}/*"
        ]
      },
      {
        # Quyền gọi Bedrock Foundation Model
        Sid    = "BedrockModelAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:GetFoundationModel"
        ]
        Resource = "*"
      },
      {
        # Quyền tương tác với AgentCore Browser Fleet (Chrome Cloud)
        Sid    = "AgentCoreBrowserAccess"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateBrowserSession",
          "bedrock-agentcore:GetBrowserSession",
          "bedrock-agentcore:StartBrowserSession",
          "bedrock-agentcore:StopBrowserSession"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==========================================
# 4. AMAZON BEDROCK AGENT (Đã sửa lỗi block ảo và model)
# ==========================================
resource "aws_bedrockagent_agent" "security_audit_agent" {
  agent_name                  = "Sydney-Infrastructure-Auditor"
  agent_resource_role_arn     = aws_iam_role.agent_execution_role.arn
  foundation_model            = "amazon.nova-pro-v1:0" # Đổi sang model chuẩn hóa hỗ trợ Nova Act tại Sydney
  instruction                 = <<EOT
Bạn là một chuyên gia tự động hóa kiểm toán bảo mật hạ tầng AWS. Khi nhận được yêu cầu (ví dụ: kiểm tra mã hóa thuộc tính Encryption của các RDS Databases), bạn sẽ sử dụng AgentCore Browser Tool để mở trình duyệt, điều hướng qua AWS Console đến đúng dịch vụ, kiểm tra cấu hình thực tế và thực hiện chụp ảnh màn hình toàn bộ trang (Full-page screenshot) để làm bằng chứng kiểm toán. Sau đó, lưu bằng chứng vào S3 bucket được chỉ định.
EOT
  idle_session_ttl_in_seconds = 1800
  prepare_agent               = true # Kích hoạt tính năng tự động chuẩn bị Agent sau khi tạo
}
