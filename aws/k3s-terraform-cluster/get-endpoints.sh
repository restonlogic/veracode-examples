#!/bin/bash

set -e

OPT="value"
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BBLUE='\033[1;34m'
PURPLE='\033[1;35m'
BYellow='\033[1;33m'
NC='\033[0m'

NAME=$(jq '.global_config.name' -r ./manifest.json)
REGION=$(jq '.global_config.region' -r ./manifest.json)
ORG=$(jq '.global_config.organization' -r ./manifest.json)
ENVIRONMENT=$(jq '.global_config.environment' -r ./manifest.json)
ext_lb_dns=$(aws elbv2 --region $REGION describe-load-balancers --names "k3s-ext-lb-$ENVIRONMENT" | jq -r '.LoadBalancers[].DNSName')

jenkins_pass=$(aws secretsmanager --region $REGION get-secret-value --secret-id /${NAME}/${ENVIRONMENT}/jenkins-secrets --query SecretString --output text | jq -r '."jenkins-admin-password"')
skooner_token=$(kubectl get secret -n default skooner-sa-token -o json | jq -r '.data.token' | base64 -d)

printf "${BLUE}**********************************************************************${NC}\n"
printf "${BBLUE}The service endpoints are listed below:${NC}\n"
echo " "
printf "${BLUE} Jenkins endpoint: ${NC}\n"
printf "  ${BBLUE} URL${NC}: http://$ext_lb_dns/jenkins/blue\n"
printf "  ${BBLUE} Credentials${NC}: admin / $jenkins_pass\n"
echo " "
printf "${BLUE} Veracode Dashboard: ${NC}\n"
printf "  ${BBLUE} URL${NC}: https://web.analysiscenter.veracode.com/\n"
echo " "
printf "${BLUE} K3s Monitoring Dashboard: ${NC}\n"
printf "  ${BBLUE} URL${NC}: http://$ext_lb_dns/\n"
printf "  ${BBLUE} Token${NC}: $skooner_token\n"
echo " "
printf "${BLUE} API Layer Services: ${NC}\n"
printf " ${ORANGE}NOTE: The counter service is being built, scanned and deployed by jenkins, the url will appear below when its done.\n please to log into jenkins to see progress and veracode to view scan results.${NC}\\n"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://$ext_lb_dns/counter-service/)" != "200" ]]; do sleep 5; done; printf "  ${BBLUE}counter service url${NC}: http://$ext_lb_dns/counter-service/\n"
printf "${BLUE}**********************************************************************${NC}\n"