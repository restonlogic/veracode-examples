#!/bin/bash
set -e

action=$1
GIT_PAT_USER=$2
GIT_PAT_TOKEN=$3
VERACODE_API_ID=$4
VERACODE_API_KEY=$5
SNOW_URL=$6
SNOW_USR=$7
SNOW_PWD=$8

NAME=$(jq '.global_config.name' -r ../manifest.json)
ENVIRONMENT=$(jq '.global_config.environment' -r ../manifest.json)
REGION=$(jq '.global_config.region' -r ../manifest.json)
BUCKET_NAME=$(aws ssm get-parameter --name "/tf/${NAME}/${ENVIRONMENT}/tfBucketName" --region $REGION | jq -r '.Parameter.Value')

if [ -z $action ]; then
    echo "$0 <action>"
    exit 1
fi

if [ -z $ENVIRONMENT ]; then
    echo "$1 <environment>"
    exit 1
fi

if [ -z $REGION ]; then
    echo "Terraform region not set or found."
    exit 1
fi

if [ -z $BUCKET_NAME ]; then
    echo "Terraform bucketname not set or found."
    exit 1
fi

echo "Deploying $ENVIRONMENT environment"
rm -rf .terraform
rm -rf .terraform.lock.hcl
terraform init \
    -backend-config="bucket=${BUCKET_NAME}" \
    -backend-config="region=$REGION" \
    -backend-config="key=${NAME}-${ENVIRONMENT}-secrets.tfstate"

terraform validate
case $action in
apply)
    echo "Running Terraform Apply Full"
    terraform apply -auto-approve -compact-warnings \
        -var-file=../manifest.json \
        -var=git_pat_user=$GIT_PAT_USER \
        -var=git_pat_token=$GIT_PAT_TOKEN \
        -var=veracode_api_id=$VERACODE_API_ID \
        -var=veracode_api_key=$VERACODE_API_KEY \
        -var=snow_url=$SNOW_URL \
        -var=snow_usr=$SNOW_USR \
        -var=snow_pwd=$SNOW_PWD
    ;;
destroy)
    echo "Running Terraform Destroy"
    terraform destroy -auto-approve -compact-warnings \
        -var-file=../manifest.json \
        -var=git_pat_user=$GIT_PAT_USER \
        -var=git_pat_token=$GIT_PAT_TOKEN \
        -var=veracode_api_id=$VERACODE_API_ID \
        -var=veracode_api_key=$VERACODE_API_KEY \
        -var=snow_url=$SNOW_URL \
        -var=snow_usr=$SNOW_USR \
        -var=snow_pwd=$SNOW_PWD
    ;;
plan)
    echo "Running Terraform Plan"
    terraform plan -compact-warnings \
        -var-file=../manifest.json \
        -var=git_pat_user=$GIT_PAT_USER \
        -var=git_pat_token=$GIT_PAT_TOKEN \
        -var=veracode_api_id=$VERACODE_API_ID \
        -var=veracode_api_key=$VERACODE_API_KEY \
        -var=snow_url=$SNOW_URL \
        -var=snow_usr=$SNOW_USR \
        -var=snow_pwd=$SNOW_PWD
    ;;
esac
