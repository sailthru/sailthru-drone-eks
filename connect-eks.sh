#!/bin/bash

set -x

# Vars definition
ci_role=${PLUGIN_USE_CI_ROLE:-'ci'}
session_id="${DRONE_COMMIT_SHA:0:10}-${DRONE_BUILD_NUMBER}"
account_id=${PLUGIN_ACCOUNT:-'none'}
aws_credentials_ttl=${PLUGIN_AWS_CREDENTIALS_TTL:-'3600'}
aws_region=${PLUGIN_AWS_REGION:-'eu-west-1'}
on_error=${PLUGIN_ON_ERROR:-'cleanup'}

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
if [ -z ${PLUGIN_EKS_CLUSTER} ]; then
  echo "EKS_CLUSTER (Name of EKS cluster) must be defined."
  exit 1
fi

if [ -z ${PLUGIN_IAM_ROLE_ARN} ]; then
  echo "IAM_ROLE_ARN (ARN of the IAM role with cluster deploy/management perms) must be defined."
  exit 1
fi

if [ -z ${PLUGIN_AWS_REGION} ]; then
  # Try to pull the region from the host that is running Drone - this assumes
  # the Drone EC2 instance is in the same region as the EKS cluster you are
  # deploying onto. If needed, override with PLUGIN_AWS_REGION param,
  export AWS_REGION_AND_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
  export PLUGIN_AWS_REGION=`echo ${AWS_REGION_AND_ZONE} | sed 's/[a-z]$//'`

fi
export AWS_DEFAULT_REGION=${PLUGIN_AWS_REGION}



# Fetch the token from the AWS account.
KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $PLUGIN_EKS_CLUSTER -r $PLUGIN_IAM_ROLE_ARN | jq -r .status.token)

if [ -z $KUBERNETES_TOKEN ]; then
  echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
  echo "Maybe it cannot assume the ${PLUGIN_IAM_ROLE_ARN} role?"
  exit 1
fi


# Fetch the EKS cluster information.
EKS_URL=$(aws eks describe-cluster --name ${PLUGIN_EKS_CLUSTER} | jq -r .cluster.endpoint)
EKS_CA=$(aws eks describe-cluster --name ${PLUGIN_EKS_CLUSTER} | jq -r .cluster.certificateAuthority.data)

if [ -z $EKS_URL ] || [ -z $EKS_CA ]; then
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
    server: ${EKS_URL}
    certificate-authority-data: ${EKS_CA}
  name: eks_${PLUGIN_EKS_CLUSTER}

contexts:
- context:
    cluster: eks_${PLUGIN_EKS_CLUSTER}
    user: eks_${PLUGIN_EKS_CLUSTER}
  name: eks_${PLUGIN_EKS_CLUSTER}

current-context: eks_${PLUGIN_EKS_CLUSTER}

users:
- name: eks_${PLUGIN_EKS_CLUSTER}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - ${PLUGIN_EKS_CLUSTER}
        - -r
        - ${PLUGIN_IAM_ROLE_ARN}
EOF
