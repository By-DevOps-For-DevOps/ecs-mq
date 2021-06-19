#!/bin/sh

set -ex

APP_NAME=$(echo "${GITHUB_REPO}" | sed 's/_/-/g')
APP_NAME=$(echo "${APP_NAME}" | sed 's/-//g')
APP_NAME=$(echo "${APP_NAME}" | cut -c1-15)

if [ "$DEPLOY_ENVIRONMENT" != "release" ] ; then
  # Docker.com authentication to solve API rate limit issue
  # https://www.docker.com/increase-rate-limits?utm_source=docker&utm_medium=web%20referral&utm_campaign=pull%20limits%20home%20page&utm_budget=
  DOCKERHUB_USER=$(aws ssm get-parameters --name "/${ENVIRONMENT_NAME}/DOCKERHUB_USER" --with-decryption --query Parameters[0].Value --output text)
  DOCKERHUB_TOKEN=$(aws ssm get-parameters --name "/${ENVIRONMENT_NAME}/DOCKERHUB_TOKEN" --with-decryption --query Parameters[0].Value --output text)
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
fi

# prints Epoch time e.g. 1595330840
date +%s > build.id

if [ "$DEPLOY_ENVIRONMENT" = "development" ] || \
   [ "$DEPLOY_ENVIRONMENT" = "feature" ] || \
   [ "$DEPLOY_ENVIRONMENT" = "hotfix" ]; then
    echo "$TAG_NAME-$BUILD_SCOPE-$(cat ./build.id)" > docker.tag
    docker build -t $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:"$(cat docker.tag)" .
    TAG=$(cat docker.tag)
elif [ "$DEPLOY_ENVIRONMENT" = "staging" ] ; then
    echo "${RELEASE_PLAN}-$BUILD_SCOPE-$(cat ./build.id)" > docker.tag
    docker build -t $AWS_ACCOUNT_ID.dkr.ecr.$ECS_REGION.amazonaws.com/$ECR_NAME:"$(cat docker.tag)" .
    TAG=$(cat docker.tag)
elif [ "$DEPLOY_ENVIRONMENT" = "release" ] ; then
    GITHUB_TOKEN=${GITHUB_TOKEN}
    git config --global user.email ${GITHUB_EMAIL}
    git config --global user.name ${GITHUB_USERNAME}
    git clone https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}
    cd ${GITHUB_REPO}
    git checkout staging
    echo "$(git log `git describe --tags --abbrev=0`..HEAD --pretty=format:"<br>- %s%b<br>")" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/<br>/g' | tr -d '\r' | sed "s/\"/'/g" > ./commits
    cat ./commits
    git tag "$(cat ../docker.tag)"
    git push --tags
    git checkout master
    git merge staging
    git push origin master

    # TODO(kamol): Remove it, this distro (ubuntu) is different from our default one (Amazon linux)
    # https://github.com/microservices-today/ecs-cicd/blob/266abc5be50e8e6168186c7a01293b4aff36c315/pipeline.yaml#L391
    # Image: "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    yum install -y jq

    # Delete released branch (e.g. 2.0.4) and let a candidate (e.g. 2.0.4-candidate-f3056cc) to be promoted
    # This case is only to support multiple pipelines
    # Get a release by tag name (https://docs.github.com/en/rest/reference/repos#get-a-release-by-tag-nametags)
    API_URI="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/tags/${RELEASE_PLAN}"
    RELEASE_STATUS=$(curl -H 'Authorization: token '${GITHUB_TOKEN}'' --write-out %{http_code} --silent --output get_release_by_tag.txt "$API_URI")
    if [ "${RELEASE_STATUS}" -eq 200 ]; then

        # Delete a release (https://docs.github.com/en/rest/reference/repos#delete-a-release)
        echo "Release found with status:${RELEASE_STATUS}. Deleting the release."
        RELEASE_ID=$(cat get_release_by_tag.txt | jq -r '.id')
        API_URI="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/${RELEASE_ID}"
        RELEASE_STATUS=$(curl -H 'Authorization: token '${GITHUB_TOKEN}'' --request DELETE --write-out %{http_code} --silent --output /dev/null "$API_URI")
        if [ "${RELEASE_STATUS}" -ne 204 ]; then
            echo "Failed to delete a release with status:${RELEASE_STATUS}."
            exit 1;
        else
            echo "Release with tag ${RELEASE_PLAN} and ID ${RELEASE_ID} is deleted."
        fi

    else
        echo "Release not found with tag ${RELEASE_PLAN} and status:${RELEASE_STATUS}."
    fi

    # Create a release (https://docs.github.com/en/rest/reference/repos#create-a-release)
    echo "Creating a new release."
    API_URI="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases"
    API_JSON=$(printf '{"tag_name": "%s","target_commitish": "master",
    "name": "%s - (Release Notes)","body": "%s",
    "draft": false,"prerelease": false}' $RELEASE_PLAN $RELEASE_PLAN "$(cat commits)")
    RELEASE_STATUS=$(curl -H 'Authorization: token '${GITHUB_TOKEN}'' --write-out %{http_code} --silent --output /dev/null --data "$API_JSON" "$API_URI")
    if [ "${RELEASE_STATUS}" -ne 201 ]; then
        echo "Release Failed with status:${RELEASE_STATUS}"
        exit 1;
    else
        echo "Release creation is completed successfully"
    fi

    cd ..
else
    echo "Entering Production Build"
    GITHUB_TOKEN=${GITHUB_TOKEN}
    git clone https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${GITHUB_REPO}
    cd "${GITHUB_REPO}"
    git checkout staging
    STAGE_TAG=$(git tag -l --sort=-v:refname '*candidate*' | head -n 1)
    TAG=$(curl -H 'Authorization: token '${GITHUB_TOKEN}'' https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/latest | grep tag_name | grep -Eo "([0-9]\.*)+")
    echo "${STAGE_TAG}" > ../stage.tag
    echo "${TAG}" > ../prod.tag
    cat ../stage.tag
    cat ../prod.tag
    cd ..
fi

if [ "$DEPLOY_ENVIRONMENT" != "release" ] ; then
  sed -i "s@APP_NAME@$APP_NAME@g" ecs/service.yaml
  sed -i "s@TAG@$TAG@g" ecs/service.yaml
  sed -i "s#EMAIL#$EMAIL#g" ecs/service.yaml
  sed -i "s@ENVIRONMENT_NAME@$ENVIRONMENT_NAME@g" ecs/service.yaml
  sed -i "s@BUILD_SCOPE@$BUILD_SCOPE@g" ecs/service.yaml
  sed -i "s@ECS_REPOSITORY_NAME@$ECR_NAME@g" ecs/service.yaml
  sed -i "s@ECS_CPU_COUNT@$ECS_CPU_COUNT@g" ecs/service.yaml
  sed -i "s@ECS_MEMORY_RESERVATION_COUNT@$ECS_MEMORY_RESERVATION_COUNT@g" ecs/service.yaml
  sed -i "s@DESIRED_COUNT@$DESIRED_COUNT@g" ecs/service.yaml

  . ecs/params.sh
  perl -i -pe 's/ENVIRONMENT_VARIABLES/`cat env.yaml`/e' ecs/service.yaml
  # Remove the env yaml (not to persist secrets)
  rm env.yaml || true
fi
