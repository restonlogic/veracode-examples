#!/usr/bin/groovy
/**
 * Create change requests and incidents in servicenow
 */
import jenkins.*
import jenkins.model.* 
import hudson.*
import hudson.model.*

def getSecretString(String secretID) {
    def jenkinsCredentials = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials( com.cloudbees.plugins.credentials.common.StandardCredentials.class, Jenkins.instance, null, null );
    for (creds in jenkinsCredentials) {
    if(creds.id == secretID){
        return (creds.getSecret())
        }
    }
}

def changeRequest(String folder, String short_description, String description, String work_notes, String category, String type, String priority, String assigned_to, String impact, String urgency) {

    def username = getSecretString('snow-usr')
    def password = getSecretString('snow-pwd')
    def url = getSecretString('snow-url')
    def types = type ?: 'Standard'
    def categorys = category ?: 'DevOps'
    def prioritys = priority ?: '3'
    def impacts = impact ?: '3'
    def urgencys = urgency ?: '3'
    def assigned_tos = assigned_to ?: 'DevOps System'

    sh """
        curl "$url/api/sn_chg_rest/change" \\
        --request POST \\
        --header "Accept: application/json" \\
        --header "Content-Type: application/json" \\
        --data-raw '{
        "short_description": "$short_description",
        "description": "$description",
        "work_notes": "$work_notes",
        "category": "$categorys",
        "type": "$types",
        "priority": "$prioritys",
        "assigned_to": "$assigned_tos",
        "impact": "$impacts",
        "urgency": "$urgencys" }' \\
        --user '$username':'$password'
    """
}