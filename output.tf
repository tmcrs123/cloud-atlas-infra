output "lambda-process_image_role_arn" {
  description = "ARN of process image lambda"
  value       = aws_iam_role.lambda-process-image-role.arn
}