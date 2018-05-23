provider "aws" {
  region = "${var.region}"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir = "lambda"
  output_path = "lambda.zip"
}

// Bucket
resource "aws_s3_bucket" "bucket" {
  bucket        = "${var.bucket}"
  acl           = "private"
  force_destroy = true
}

resource "aws_iam_role" "role" {
  name = "uploader_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "policy" {
  name = "uploader_policy"
  role = "${aws_iam_role.role.id}"

  policy = <<EOF
{
    "Statement": [
        {
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:GetObjectVersion",
                "s3:PutObject",
                "s3:GetLifecycleConfiguration",
                "s3:PutLifecycleConfiguration"
            ],
            "Resource": [
                "arn:aws:s3:::jonatasrenan-s3-uploader",
                "arn:aws:s3:::jonatasrenan-s3-uploader/*"
            ],
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "basic-exec-lambda-role" {
    role       = "${aws_iam_role.role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

//Lambda
resource "aws_lambda_function" "lambda" {
  function_name = "s3-uploader_${var.bucket}_lambda"
  filename = "lambda.zip"
  source_code_hash = "${base64sha256(file("lambda.zip"))}"
  handler = "src/index.handler"
  runtime = "nodejs6.10"
  memory_size = "1536"
  timeout = "60"
  role = "${aws_iam_role.role.arn}"
  environment {
    variables = {
      DEST_BUCKET = "jonatasrenan-s3-uploader"
    }
  }
}


# Api
resource "aws_api_gateway_rest_api" "api" {
  name        = "ServerlessExample"
  description = "Terraform Serverless Application Example"
  binary_media_types = ["*/*"]
}


# Methods
resource "aws_api_gateway_method" "proxy_get" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy_post" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  http_method   = "GET"
  authorization = "NONE"
}

# Resource
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path_part   = "{proxy+}"
}


# Integrations
resource "aws_api_gateway_integration" "lambda_get" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_method.proxy_get.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_get.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"
}

resource "aws_api_gateway_integration" "lambda_post" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_method.proxy_post.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_post.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.lambda.invoke_arn}"
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    "aws_api_gateway_integration.lambda_get",
    "aws_api_gateway_integration.lambda_post",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "test"
}

# Stages
resource "aws_api_gateway_stage" "Prod" {
  stage_name = "prod"
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  deployment_id = "${aws_api_gateway_deployment.deployment.id}"
}

resource "aws_api_gateway_stage" "Stage" {
  stage_name = "stage"
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  deployment_id = "${aws_api_gateway_deployment.deployment.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.deployment.execution_arn}/*/*"
}

output "base_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}"
}
