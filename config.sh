aws_region="${AWS_REGION:-}"
aws_instance_type="t3.micro"
aws_keyname="${AWS_KEYNAME:-}"
# NOTE: Ensure security group has ssh access
aws_security_group="${AWS_SECURITYGROUP:-}"
aws_instance_name="amazon-ec2-net-utils-test"

aws_ami="ami-0fe8bec493a81c7da"
