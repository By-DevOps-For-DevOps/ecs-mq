#!/usr/bin/env bash

set -ex

if [ "$DEPLOY_ENVIRONMENT" = "development" ] || \
   [ "$DEPLOY_ENVIRONMENT" = "staging" ] || \
   [ "$DEPLOY_ENVIRONMENT" = "feature" ] || \
   [ "$DEPLOY_ENVIRONMENT" = "hotfix" ]; then
    aws ecr get-login-password --region ${ECS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com
    echo ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./docker.tag)
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./docker.tag)
elif [ "$DEPLOY_ENVIRONMENT" = "production" ]; then
    aws ecr get-login-password --region ${SOURCE_AWS_REGION} | docker login --username AWS --password-stdin ${SOURCE_AWS_ACCOUNT_ID}.dkr.ecr.${SOURCE_AWS_REGION}.amazonaws.com
    docker pull ${SOURCE_AWS_ACCOUNT_ID}.dkr.ecr.${SOURCE_AWS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./stage.tag)
    docker tag ${SOURCE_AWS_ACCOUNT_ID}.dkr.ecr.${SOURCE_AWS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./stage.tag) ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./prod.tag)
    aws ecr get-login-password --region ${ECS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com
    docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${ECS_REGION}.amazonaws.com/${ECR_NAME}:$(cat ./prod.tag)
else
    echo "NO POST BUILD ACTIONS IN RELEASE"
fi
