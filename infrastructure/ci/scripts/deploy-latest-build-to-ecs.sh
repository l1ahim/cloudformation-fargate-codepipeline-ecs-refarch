#!/bin/bash
set -e

ENV_NAME_ARG=$1

IMAGE_TAG=$(
    aws ecr \
        describe-repositories \
        --repository-names ${ENV_NAME_ARG} \
        --query 'repositories[0].repositoryUri' | sed -e 's;\";;g'):latest

SERVICE_ARN=$(
    aws cloudformation \
        describe-stacks \
        --query 'Stacks[0].Outputs[?OutputKey==`WebServiceArn`].OutputValue' \
        --stack-name ${ENV_NAME_ARG} | jq '.[0]' | sed -e "s;\";;g")

STACK_NAME=$(
    aws cloudformation \
        describe-stacks \
        --query 'Stacks[0].Outputs[?OutputKey==`WebServiceStackName`].OutputValue' \
        --stack-name ${ENV_NAME_ARG} | jq '.[0]' | sed -e "s;\";;g")

TASK_EXECUTION_ROLE_ARN=$(
    aws cloudformation \
        describe-stacks \
        --query 'Stacks[0].Outputs[?OutputKey==`WebServiceTaskExecutionRoleArn`].OutputValue' \
        --stack-name ${ENV_NAME_ARG} | jq '.[0]' | sed -e "s;\";;g")

SERVICE_REGION=$(echo ${SERVICE_ARN} | sed -e "s;.*ecs:;;g" -e "s;:.*;;g")

SERVICE_NAME=$(echo ${SERVICE_ARN} | sed -e "s;.*/;;g")

TASK_FILE="./build-$(date +%s).json"

sed -e "s;%IMAGE_TAG%;${IMAGE_TAG};g" \
    -e "s;%STACK_NAME%;${STACK_NAME};g" \
    -e "s;%AWSLOGS_REGION%;${SERVICE_REGION};g" \
    ./infrastructure/ci/templates/task-definition.json > ${TASK_FILE}

TASK_REVISION=$(
    aws ecs \
        register-task-definition \
        --family web-service \
        --cpu 256 \
        --memory 512 \
        --requires-compatibilities FARGATE \
        --task-role-arn ${TASK_EXECUTION_ROLE_ARN} \
        --execution-role-arn ${TASK_EXECUTION_ROLE_ARN} \
        --network-mode awsvpc \
        --cli-input-json "file://${TASK_FILE}" | jq '.["taskDefinition"]["revision"]')

aws ecs update-service --cluster ${ENV_NAME_ARG} --service ${SERVICE_NAME} --task-definition web-service:${TASK_REVISION}

rm ${TASK_FILE}

echo "$(date):${0##*/}:success"