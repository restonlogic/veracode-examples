controller:
  runAsUser: 0
  fsGroup: 0
  containerSecurityContext:
    runAsUser: 0
    runAsGroup: 0
    readOnlyRootFilesystem: false
    allowPrivilegeEscalation: false
  numExecutors: 6
  executorMode: "NORMAL"
  image: "engrave/jenkins-veracode-example"
  tag: "latest"
  adminSecret: true
  adminPassword: "${jenkins_admin_password}"
  serviceType: NodePort
  servicePort: 80
  targetPort: 80
  agentListenerServiceType: NodePort
  serviceExternalTrafficPolicy: Local
  jenkinsUriPrefix: "/jenkins"
  csrf:
    defaultCrumbIssuer:
      enabled: true
      proxyCompatibility: true
  resources:
    requests:
      cpu: "50m"
      memory: "256Mi"
    limits:
      cpu: "1024m"
      memory: "2048Mi"
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: admin
          name: admin
          password: "${jenkins_admin_password}"
  permissive-script-security:
    enabled: true
  installPlugins:
    - kubernetes:1.31.2
    - git:latest
    - configuration-as-code:latest
    - workflow-aggregator:2.6
  additionalPlugins:
    - ansicolor:latest
    - authorize-project:latest
    - build-timeout:latest
    - cloudbees-folder:latest
    - credentials-binding:latest
    - credentials:latest
    - docker-workflow:1.26
    - email-ext:latest
    - envinject:latest
    - environment-script:1.2.5
    - github:latest
    - job-dsl:latest
    - matrix-auth:latest
    - maven-plugin:3.16
    - parameterized-scheduler:latest
    - permissive-script-security:0.7
    - pipeline-aws:latest
    - pipeline-build-step:latest
    - pipeline-model-definition:latest
    - pipeline-stage-view:latest
    - pipeline-utility-steps:latest
    - rebuild:latest
    - ssh:2.6.1
    - solarized-theme:0.1
    - timestamper:latest
    - workflow-cps-global-lib:latest
    - workflow-job:latest
    - ws-cleanup:latest
    - prometheus:latest
    - http_request:1.14
    - durable-task:500.v8927d9fd99d8
    - sonar:2.14
    - htmlpublisher:1.30
    - veracode-scan:22.6.18.0

  JCasC:
    defaultConfig: true
    configScripts:
      welcome-message: |-
        jenkins:
          systemMessage: "Welcome to the Veracode K3s Microservices Demo!"

        credentials:
          system:
            domainCredentials:
              - credentials:
                - usernamePassword:
                    description: "git-creds"
                    id: "git-creds"
                    scope: GLOBAL
                    password: ${git_access_token}
                    username: ${git_username}
                - string:
                    scope: GLOBAL
                    id: "gitops-address"
                    secret: ${gitops_address}
                    description: "gitops address"
                - string:
                    scope: GLOBAL
                    id: "gitops-org"
                    secret: ${gitops_org}
                    description: "gitops org"
                - string:
                    scope: GLOBAL
                    id: "gitops-repo"
                    secret: ${gitops_repo}
                    description: "gitops repo"
                - string:
                    scope: GLOBAL
                    id: "gitops-branch"
                    secret: ${gitops_branch}
                    description: "gitops branch"
                - string:
                    scope: GLOBAL
                    id: "gitops_full_url"
                    secret: "${gitops_full_url}"
                    description: "gitops full url"
                - string:
                    scope: GLOBAL
                    id: "gitops-org-url"
                    secret: "${gitops_org_url}"
                    description: "gitops org url"

        security:
          globaljobdslsecurityconfiguration:
            useScriptSecurity: false

        unclassified:
          globalLibraries:
            libraries:
              - name: "jenkins-library"
                allowVersionOverride: true
                defaultVersion: "main"
                implicit: true
                retriever:
                  modernSCM:
                    scm:
                      git:
                        id: 'jenkins-library'
                        remote: "${gitops_full_url}"
                        credentialsId: 'git-creds'

        jobs:
          - script: >
              pipelineJob("set-folders") {
                  description("Pipeline Job for setting the folder structure of the Jenkins server")
                  definition {
                      cpsScm {
                          scm {
                              git {
                                  branch("main")
                                  remote {
                                      credentials("git-creds")
                                      url("${gitops_full_url}")
                                  }
                              }
                              scriptPath("aws/k3s-terraform-cluster/pipelines-as-code/jenkins/bootstrap/set-folders/Jenkinsfile.groovy")
                          }
                      }
                  }
              }

          - script: >
              job("single-seed-job") {
                  description("Freestyle Job that builds a single other job")
                  parameters {
                      stringParam("job_dsl_path", "", "Location of Job DSL script")
                  }
                  concurrentBuild(true)
                  scm {
                      git {
                          branch("main")
                          remote {
                              credentials("git-creds")
                              url("${gitops_full_url}")
                          }
                      }
                  }
                  steps {
                      dsl {
                          external("\$job_dsl_path")
                      }
                  }
              }
          - script: >
              job("seed-job") {
                  description("Freestyle Job that builds other jobs")
                  concurrentBuild(false)
                  scm {
                      git {
                          branch("main")
                          remote {
                              credentials("git-creds")
                              url("${gitops_full_url}")
                          }
                      }
                  }
                  steps {
                      dsl {
                          external("**/job_dsl.groovy")
                      }
                  }
              }
          - script: >
              pipelineJob("bootstrap-pipeline-job") {
                  description("Pipeline Job for initializing the Jenkins server, this job triggers when Jenkins spins up for the first time and when there is changes to the pipelines directory.")
                  triggers {
                        scm('* * * * *')
                  }
                  definition {
                      cpsScm {
                          scm {
                              git {
                                  branch("main")
                                  remote {
                                      credentials("git-creds")
                                      url("${gitops_full_url}")
                                  }
                              }
                              scriptPath("aws/k3s-terraform-cluster/pipelines-as-code/jenkins/bootstrap/init/Jenkinsfile.groovy")
                          }
                      }
                  }
              }
  sidecars:
    configAutoReload:
      enabled: true
      image: kiwigrid/k8s-sidecar:1.21.0
      imagePullPolicy: IfNotPresent
      resources: {}
      reqRetryConnect: 10
      sshTcpPort: 1044
      folder: "/var/jenkins_home/casc_configs"
      containerSecurityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: true
    other:
      - name: dind
        image: docker:dind
        securityContext:
          privileged: true
        resources:
          requests:
            memory: "1024Mi"
            cpu: "1"
          limits:
            memory: "2048Mi"
            cpu: "2"
        env:
        - name: DOCKER_HOST
          value: tcp://docker:2375/
        - name: DOCKER_DRIVER
          value: overlay2
        - name: DOCKER_TLS_CERTDIR
          value: ""
  ingress:
    enabled: true
    apiVersion: "networking.k8s.io/v1"
    ingressClassName: nginx
    path: "/jenkins"
healthProbes: true
livenessProbe:
    httpGet:
      path: "/jenkins/login"
      port: 80
    initialDelaySeconds: 90
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 5
readinessProbe:
  httpGet:
    path: "/jenkins/login"
    port: 80
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
serviceAccount:
  create: true
  name: "jenkins-sa"
persistence:
  enabled: true
  accessMode: "ReadWriteMany"
  size: "100Gi"
  storageClass: efs-sc
agent:
  envVars:
    - name: DOCKER_HOST
      value: tcp://localhost:2375