#!/bin/bash

set -x

# Get variables from config.sh
source config.sh

ssh_flags=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null "
ssh_key="~/.ssh/${aws_keyname}.pem"

wait_for_ssh() {
    # $1 is ipaddr
    local max_ssh_attempts=10
    local ssh_attempt_sleep_time=10
    local ipaddr=$1

    # Loop until SSH is successful or max_attempts is reached
    for ((i = 1; i <= $max_ssh_attempts; i++)); do
        ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} exit
        if [ $? -eq 0 ]; then
            echo "SSH connection successful."
            break
        else
            echo "Attempt $i: SSH connection failed. Retrying in $ssh_attempt_sleep_time seconds..."
            sleep $ssh_attempt_sleep_time
        fi
    done

    if [ $i -gt $max_ssh_attempts ]; then
        echo "Max SSH connection attempts reached. Exiting."
    fi
}

#aws_ami=$( aws ec2 describe-images \
#	--owners 099720109477 \
#	--region $region \
#	--filters "Name=name,Values=ubuntu/${image_type}/*${distro}*${arch}*" \
#	--query 'Images[*].[ImageId,CreationDate,Name]' \
#	--output text \
#	| sort -k2 -r | head -n1 | awk '{print $1}'
#)

# This approach creates a new EC2 instance and also creates a new subnet_id. Maybe create a specific new subnet_id?

instance_id=$(aws ec2 run-instances \
    --region ${aws_region} \
    --image-id ${aws_ami} \
    --count 1 \
    --instance-type ${aws_instance_type} \
    --key-name ${aws_keyname} \
    --security-group-ids ${aws_security_group} \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${aws_instance_name}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

subnet_id=$(aws ec2 describe-instances \
  --region $aws_region \
  --instance-ids $instance_id \
  --query 'Reservations[].Instances[].SubnetId' \
  --output text)

# Create new ENI
eni_id=$(aws ec2 create-network-interface \
  --region $aws_region \
  --subnet-id $subnet_id \
  --description "amazon-ec2-net-utils-test" \
  --groups $aws_security_group \
  --query 'NetworkInterface.NetworkInterfaceId' \
  --output text)

aws ec2 attach-network-interface \
  --region $aws_region \
  --network-interface-id $eni_id \
  --instance-id $instance_id \
  --device-index 1


aws ec2 wait instance-running --region $aws_region --instance-ids $instance_id
ipaddr=$(aws ec2 describe-instances --instance-ids $instance_id --region $aws_region \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

wait_for_ssh $ipaddr

# Enable proposed
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    'echo "deb http://archive.ubuntu.com/ubuntu $(lsb_release -cs)-proposed restricted main multiverse universe" | sudo tee /etc/apt/sources.list.d/ubuntu-$(lsb_release -cs)-proposed.list' 

## install amazon-ec2-net-utils
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    'sudo apt-get update -y && sudo apt-get install -y amazon-ec2-net-utils -t $(lsb_release -cs)-proposed'

# Check version
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    dpkg -l amazon-ec2-net-utils | grep amazon-ec2-net-utils | awk '{print $3}'

# Apply netplan to make addresses come up
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    'sudo rm /etc/netplan/50-cloud-init.yaml'
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    'sudo netplan apply'

# Now at this point, we should have 2 NICs with 2 different IP addresses.
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} 'sudo ip a'
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} 'sudo ip rule show'
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} 'sudo ip route show'
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} 'sudo ip route show table 10001'
ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} 'sudo ip route show table 10002'

version=$(ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} \
    dpkg -l amazon-ec2-net-utils | grep amazon-ec2-net-utils | awk '{print $3}')

echo "amazon-ec2-net-utils $version tested"

# TODO: cleanup, analyze results properly
