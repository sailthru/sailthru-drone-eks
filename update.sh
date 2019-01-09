#!/bin/bash

# Perform a deployment onto Kubernetes by updating an existing K8s deployment
# with a new container image.
#

# Connect to the EKS cluster.
source /bin/connect-eks.sh

# Make sure we have information needed for deployment.
if [ -z ${PLUGIN_REPO} ]; then
  echo "REPO must be defined"
  exit 1
fi

if [ -z ${PLUGIN_TAG} ]; then
  echo "TAG must be defined"
  exit 1
fi

if [ -z ${PLUGIN_NAMESPACE} ]; then
  echo "NAMESPACE must be defined"
  exit 1
fi

if [ -z ${PLUGIN_DEPLOYMENT} ]; then
  echo "DEPLOYMENT must be defined"
  exit 1
fi

if [ -z ${PLUGIN_CONTAINER} ]; then
  echo "CONTAINER must be defined"
  exit 1
fi


# Perform the new deployment.
IFS=',' read -r -a DEPLOYMENTS <<< "${PLUGIN_DEPLOYMENT}"
IFS=',' read -r -a CONTAINERS <<< "${PLUGIN_CONTAINER}"
for DEPLOY in ${DEPLOYMENTS[@]}; do
  echo "Deploying to ${PLUGIN_EKS_CLUSTER} (${EKS_URL})"
  for CONTAINER in ${CONTAINERS[@]}; do
    kubectl -n ${PLUGIN_NAMESPACE} set image deployment/${DEPLOY} \
      ${CONTAINER}=${PLUGIN_REPO}:${PLUGIN_TAG} --record
  done
done
