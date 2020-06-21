#!/usr/bin/env bash
KEYS=`awk -F"=" '{print $1}' .env.sample`
for KEY in $KEYS
do
  PARAM=`aws ssm get-parameters --name "/${ENVIRONMENT_NAME}/${KEY}" --with-decryption --query Parameters[0].Value`
  printf "        - Name: ${KEY}\n" >> env.yaml
  printf "          Value: ${PARAM}\n" >> env.yaml
done
