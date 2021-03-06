FROM python:3.8-alpine

# Install base utilities
RUN apk --no-cache add curl ca-certificates bash jq groff less
RUN pip --no-cache-dir install awscli deepmerge

# Download the Amazon blessed utilities as per:
# https://docs.aws.amazon.com/eks/latest/userguide/configure-kubectl.html
ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.15.10/2020-02-22/bin/linux/amd64/kubectl /usr/bin/kubectl
ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.15.10/2020-02-22/bin/linux/amd64/aws-iam-authenticator /usr/bin/aws-iam-authenticator
RUN chmod +x /usr/bin/kubectl /usr/bin/aws-iam-authenticator

# Install the Drone plugin scripts
COPY update.sh /bin/
COPY connect-eks.sh /bin/

ENTRYPOINT ["/bin/bash"]
CMD ["/bin/update.sh"]
