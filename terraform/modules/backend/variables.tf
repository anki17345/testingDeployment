variable "bucket_name" {
  description = "Name of the S3 bucket"
  default     = "opbackendapi-terraform-state-backend-01"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  default     = "opbackendapi-db-terraform-state"
}