#!/usr/bin/groovy
/**
 * Create change requests and incidents in servicenow
 */
import jenkins.*
import jenkins.model.* 
import hudson.*
import hudson.model.*
import java.lang.String
import groovy.transform.Field

def getSecretString(String secretID) {
    def jenkinsCredentials = com.cloudbees.plugins.credentials.CredentialsProvider.lookupCredentials( com.cloudbees.plugins.credentials.common.StandardCredentials.class, Jenkins.instance, null, null );
    for (creds in jenkinsCredentials) {
    if(creds.id == secretID){
        return (creds.getSecret())
        }
    }
}

@Field username = getSecretString('snow-usr')
@Field password = getSecretString('snow-pwd')
@Field url = getSecretString('snow-url')

def changeRequest(String short_description, String description, String work_notes, String category, String type, String priority, String assigned_to, String impact, String urgency) {

    def types = type ?: 'Standard'
    def categorys = category ?: 'DevOps'
    def prioritys = priority ?: '3'
    def impacts = impact ?: '3'
    def urgencys = urgency ?: '3'
    def assigned_tos = assigned_to ?: 'DevOps System'
    def change = sh (returnStdout: true, script: """
        curl -s "$url/api/sn_chg_rest/change" --request POST --header "Accept: application/json" --header "Content-Type: application/json" --user '$username':'$password' \\
        --data-raw '{
        "short_description": "$short_description",
        "description": "$description",
        "work_notes": "$work_notes",
        "category": "$categorys",
        "type": "$types",
        "priority": "$prioritys",
        "assigned_to": "$assigned_tos",
        "impact": "$impacts",
        "urgency": "$urgencys" }' | jq -r '.result.sys_id.value'
    """).split()
    return change
}

def problem(String short_description, String description, String change_sys_id) {
    def problem = sh (returnStdout: true, script: """
        curl -s "$url/api/now/table/problem" --request POST --header "Accept: application/json" --header "Content-Type: application/json" --user '$username':'$password' \\
        --data-raw '{
        "short_description": "$short_description",
        "description": "$description",
        "rfc": {
            "link": "$url/api/now/table/change_request/$change_sys_id"
            "value" "$change_sys_id"
        } | jq -r '.result.sys_id'
    """).split()
    return problem
}