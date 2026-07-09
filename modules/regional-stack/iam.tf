data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name_prefix        = "${var.name_prefix}-role-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json

  tags = var.tags
}

# SSM Session Manager access so the instance can be reached without opening
# port 22 or managing a key pair.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Placeholder self-describe permissions. Expand this once the Akeyless
# Gateway's AWS auth method / cloud identity requirements are known (e.g.
# additional Secrets Manager or SSM Parameter Store access).
data "aws_iam_policy_document" "gateway_inline" {
  statement {
    sid = "AllowSelfDescribe"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "gateway_inline" {
  name   = "${var.name_prefix}-inline-policy"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.gateway_inline.json
}

resource "aws_iam_instance_profile" "gateway" {
  name_prefix = "${var.name_prefix}-profile-"
  role        = aws_iam_role.gateway.name
}
