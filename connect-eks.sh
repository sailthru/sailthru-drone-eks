#!/bin/bash

set -x

# Vars definition
ci_role=${PLUGIN_USE_CI_ROLE:-'ci'}
session_id="${DRONE_COMMIT_SHA:0:10}-${DRONE_BUILD_NUMBER}"
account_id=${PLUGIN_ACCOUNT:-'none'}
aws_credentials_ttl=${PLUGIN_AWS_CREDENTIALS_TTL:-'3600'}
aws_region=${PLUGIN_AWS_REGION}
on_error=${PLUGIN_ON_ERROR:-'cleanup'}
role_arn="arn:aws:iam::${account_id}:role/${ci_role}"
eks_cluster=${PLUGIN_EKS_CLUSTER:-'NOT_SET'}

# Manage mult-account
#
if [ "${account_id}" == "none" ]; then
  account_id="IAM Role"
fi

# Print authentication infos
echo "AWS credentials meta:"
echo "  CI Role: ${ci_role}"
echo "  Account ID: ${account_id}"
echo "  IAM Role Session ID: ${session_id}"
echo "  IAM Credentials TTL: ${aws_credentials_ttl}"

# Check the aws_region is set. If not, retrieve it.
if [ -z ${aws_region} ]; then
  # Try to pull the region from the host that is running Drone - this assumes
  # the Drone EC2 instance is in the same region as the EKS cluster you are
  # deploying onto. If needed, override with PLUGIN_AWS_REGION param,
  export aws_region_and_zone=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
  export aws_region=`echo ${aws_region_and_zone} | sed 's/[a-z]$//'`

fi
export AWS_DEFAULT_REGION=${aws_region}

# Get authentified if a role is specified
if [ "${account_id}" != "IAM Role" ]; then
  iam_creds=$(aws sts assume-role --role-arn "arn:aws:iam::${account_id}:role/${ci_role}" --role-session-name "drone-${session_id}" --duration-seconds ${aws_credentials_ttl} --region ${aws_region} | python -m json.tool)

  if [ -z "${iam_creds}" ]; then
    echo "ERROR: Unable to assume AWS role"
    exit 1
  fi

  export AWS_ACCESS_KEY_ID=$(echo "${iam_creds}" | grep AccessKeyId | tr -d '" ,' | cut -d ':' -f2)
  export AWS_SECRET_ACCESS_KEY=$(echo "${iam_creds}" | grep SecretAccessKey | tr -d '" ,' | cut -d ':' -f2)
  export AWS_SESSION_TOKEN=$(echo "${iam_creds}" | grep SessionToken | tr -d '" ,' | cut -d ':' -f2)
fi

# Establish an authenticated connection to an EKS cluster.
#
if [ -z ${eks_cluster} ]; then
  echo "PLUGIN_EKS_CLUSTER (Name of EKS cluster) must be defined."
  exit 1
fi

# Fetch the token from the AWS account.
#KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $eks_cluster -r $role_arn | jq -r .status.token)
#
#if [ -z $KUBERNETES_TOKEN ]; then
#  echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
#  echo "Maybe it cannot assume the ${role_arn} role?"
#  exit 1
#fi


# Fetch the EKS cluster information.
eks_url=$(aws eks describe-cluster --name ${eks_cluster} | jq -r .cluster.endpoint)
eks_ca=$(aws eks describe-cluster --name ${eks_cluster} | jq -r .cluster.certificateAuthority.data)

if [ -z $eks_url ] || [ -z $eks_ca ]; then
  echo "Unable to obtain EKS cluster information - check Drone's EKS API permissions"
  exit 1
fi


# Generate configuration files
mkdir ~/.kube
cat > ~/.kube/config << EOF
apiVersion: v1
preferences: {}
kind: Config

clusters:
- cluster:
    server: ${eks_url}
    certificate-authority-data: ${eks_ca}
  name: eks_${eks_cluster}

contexts:
- context:
    cluster: eks_${eks_cluster}
    user: eks_${eks_cluster}
  name: eks_${eks_cluster}

current-context: eks_${eks_cluster}

users:
- name: eks_${eks_cluster}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - ${eks_cluster}
        - -r
        - ${role_arn}
EOF
