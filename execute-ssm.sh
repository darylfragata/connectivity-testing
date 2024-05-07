#!/bin/bash
################################################
# Define the source system
SIDS=("HCQ" "GTQ" "TPD" "EPD")


# Define target hosts and ports for each SID
declare -A HOSTS_AND_PORTS
HOSTS_AND_PORTS["GTQ"]="google.com:440-445,79-81|bpi.com.ph|example.com:22,443,80,123|openai.com:443,8080|facebook.com:443,80"
HOSTS_AND_PORTS["HCQ"]="example.org:443,8080|test.com:443,22|openai.com:443,8080-8085|facebook.com:440-445,78-83|youtube.com:443,80,22"
HOSTS_AND_PORTS["TPD"]="142.251.220.238:440-445,79-81|bpi.com.ph|142.251.220.238:22,443,80,123|openai.com:443,8080|facebook.com:443,80"
HOSTS_AND_PORTS["EPD"]="142.251.220.238:440-445,79-81|bpi.com.ph|142.251.220.238:22,443,80,123|openai.com:443,8080|facebook.com:443,80"


AWS_REGION="ap-northeast-1"
DOCUMENT_NAME="ConnTest"
DOCUMENT_VERSION="\$DEFAULT"
ASSUME_ROLE_ARN="arn:aws:iam::458198004777:role/partial-hours-role"
S3_BUCKET="s3://dfragata-test-bucket/connectivity-output/"
SID_TAG_KEY="APPID"
#################################################

# Array to store Automation Execution IDs
AUTOMATION_EXECUTION_IDS=()

# Loop through SIDs and execute the command for each SID
for SID in "${SIDS[@]}"
do
  echo "Executing command for SID: $SID"
  execution_id=$(aws ssm start-automation-execution \
    --document-name "$DOCUMENT_NAME" \
    --document-version "$DOCUMENT_VERSION" \
    --parameters '{"AutomationAssumeRole":["'$ASSUME_ROLE_ARN'"],"HostsAndPorts":["'$(IFS=","; echo "${HOSTS_AND_PORTS[$SID]}")'"],"s3Bucket":["'$S3_BUCKET'"],"SID":["'$SID'"],"SIDTagKey":["'$SID_TAG_KEY'"]}' \
    --region "$AWS_REGION" \
    --query 'AutomationExecutionId' \
    --output text)
    
  AUTOMATION_EXECUTION_IDS+=("$execution_id,$SID")
done
echo ''
# Check the status of each Automation Execution ID
overall_status="Success"
for execution_id_sid in "${AUTOMATION_EXECUTION_IDS[@]}"
do
  execution_id=$(echo "$execution_id_sid" | cut -d ',' -f 1)
  SID=$(echo "$execution_id_sid" | cut -d ',' -f 2)
  echo "Waiting for execution ID $execution_id for SID: $SID to complete..."
  status="InProgress"
  while [ "$status" == "InProgress" ]
  do
    status=$(aws ssm describe-automation-executions \
      --region "$AWS_REGION" \
      --query 'AutomationExecutionMetadataList[?AutomationExecutionId==`'$execution_id'`].AutomationExecutionStatus' \
      --output text)
    
    if [ "$status" == "InProgress" ]; then
      sleep 10
    fi
  done

  echo "Status for $execution_id for SID: $SID: $status"$'\n'
  
  if [ "$status" != "Success" ]; then
    overall_status="Failed"
  fi
done

echo "Overall Status: $overall_status"

# Function to invoke Lambda function if successful
invoke_lambda_function() {
  local overall_status="$1"
  if [ "$overall_status" == "Success" ]; then
    echo "Overall command was successful. Invoking Lambda function to compile all the CSV files..."
    # Replace "your-lambda-function-name" with your actual Lambda function name
    aws lambda invoke --function-name csv-compiler --region ap-northeast-1 output.json
  else
    echo "Overall command was not successful. Current Status: $overall_status"
  fi
}

invoke_lambda_function "$overall_status"