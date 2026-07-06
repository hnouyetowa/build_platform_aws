output "carpenter_role_arn" {
  description = "IRSA role ARN for the Karpenter controller — annotate the karpenter ServiceAccount"
  value       = aws_iam_role.karpenter.arn
}

output "interruption_queue_name" {
  description = "SQS queue name for Spot interruption events — set as settings.interruptionQueue in Karpenter Helm values"
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_url" {
  description = "SQS queue URL for Spot interruption events"
  value       = aws_sqs_queue.interruption.url
}

output "instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes — MUST match EC2NodeClass spec.instanceProfile"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "instance_profile_arn" {
  description = "Instance profile ARN for Karpenter-launched nodes"
  value       = aws_iam_instance_profile.karpenter_node.arn
}
