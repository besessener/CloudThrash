#!/bin/bash

set -e

pushd $(dirname $0) > /dev/null

echo "### SECTION [1/4] Initializing ###"

. ./variables.sh
./check-dependencies.sh
./create-variables.sh
./deploy-docker-container.sh

echo "### SECTION [2/4] Creating Infrastructure ###"

./init-terraform-backend.sh

pushd ../terraform > /dev/null
terraform apply -auto-approve

# Extract the ECS cluster name and AWS region from the Terraform output
UNIQUE_TIMESTAMP=$(terraform output -raw unique_timestamp)

# Function to get the running task ARN
get_running_task_arn() {
  TASK_ARN=$(aws ecs list-tasks \
    --cluster $ECS_CLUSTER_NAME \
    --family loadtesting-task-leader-$UNIQUE_TIMESTAMP \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'taskArns[0]' \
    --output text)
}

# Wait for the task to start
echo "### SECTION [3/4] Waiting for Task Execution ###"
while true; do
  get_running_task_arn
  if [ "$TASK_ARN" != "None" ]; then
    echo "Found running ECS task with ARN: $TASK_ARN"
    break
  fi
  echo "No running task found yet. Checking again in 10 seconds..."
  sleep 10
done

# Function to check the status of the ECS task
echo "### SECTION [4/4] Monitoring Task Status ###"
check_task_status() {
  TASK_STATUS=$(aws ecs describe-tasks \
    --cluster $ECS_CLUSTER_NAME \
    --tasks $TASK_ARN \
    --region $AWS_REGION \
    --profile $AWS_PROFILE \
    --query 'tasks[0].lastStatus' \
    --output text)
  echo "Current task status: $TASK_STATUS"
}

# Initial task status check
check_task_status

# Wait for the task to complete
while [[ "$TASK_STATUS" != "STOPPED" ]]; do
  sleep 10
  check_task_status
done

popd > /dev/null

set +e
./list-result.sh
status=$?
set -e

popd > /dev/null

if [ $status -eq 0 ]; then
    echo "Test execution completed successfully."
elif [ $status -eq 1 ]; then
    echo "Test execution failed."
else
    echo "Test execution status is unknown, probably aborted."
fi

exit $status
