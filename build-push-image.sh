TAG=1.14.6
DEST=docker.sailthru.com/cicd/drone-eks-plugin
docker build -t ${DEST}:${TAG} .
docker tag ${DEST}:${TAG} ${DEST}:latest
docker push ${DEST}:${TAG}
docker push ${DEST}:latest