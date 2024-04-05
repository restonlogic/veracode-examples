#!/bin/bash

set -e

ENVIRONMENT=$1

NAME=$(jq '.global_config.name' -r ./manifest.json)
REGION=$(jq '.global_config.region' -r ./manifest.json)
ORG=$(jq '.global_config.organization' -r ./manifest.json)

k3s_kubeconfig=/tmp/k3s_kubeconfig_$ENVIRONMENT
aws secretsmanager --region $REGION get-secret-value --secret-id k3s-kubeconfig-${NAME}-${ENVIRONMENT}-${ORG}-${ENVIRONMENT}-v2 | jq -r '.SecretString' > $k3s_kubeconfig
ext_lb_dns=$(aws elbv2 --region $REGION describe-load-balancers --names "k3s-ext-lb-$ENVIRONMENT" | jq -r '.LoadBalancers[].DNSName')
k3s_ext_lb_dns=$(echo https://${ext_lb_dns}:6443)
yq -i -e ".clusters[].cluster.server = \"$k3s_ext_lb_dns\"" /tmp/k3s_kubeconfig_$ENVIRONMENT
export KUBECONFIG=$k3s_kubeconfig

echo "run the following:"
echo "export KUBECONFIG=/tmp/k3s_kubeconfig_$ENVIRONMENT"