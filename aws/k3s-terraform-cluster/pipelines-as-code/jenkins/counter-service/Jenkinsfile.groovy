@Library(['jenkins-library@main']) _
def buildNumber = env.BUILD_NUMBER
def buildUrl = env.BUILD_URL
def change_sys_id
def problem_sys_id
def incident_sys_id
pipeline {
    agent { label 'built-in' }
    options {
        ansiColor('xterm')
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
        buildDiscarder(
            logRotator(daysToKeepStr: '10', numToKeepStr: '5')
        )
    }

  stages {
      stage("Checkout Repository") {
          steps {
              script {
                gitopsOrgUrl = genericsteps.getSecretString('gitops-org-url')
                repo = genericsteps.getSecretString('gitops-repo')
                branch = genericsteps.getSecretString('gitops-branch')
                repoFolder  = "/repos/${repo}"
                projectDir  = "${repoFolder}/aws/k3s-terraform-cluster"
                genericsteps.checkoutGitRepository("${repoFolder}", "${gitopsOrgUrl}/${repo}.git", "${branch}", 'git-creds')
              }
          }
      }
      
      stage ("Pre-Build Setup") {
        steps {
          script {
            dir("${projectDir}") {
              sh """
                echo "Setting env variables"
                """
                image      = "counter-service"
                env        = sh(script: "jq '.global_config.environment' -r manifest.json", returnStdout: true).trim()
                name       = sh(script: "jq '.global_config.name' -r manifest.json", returnStdout: true).trim()
                region     = sh(script: "jq '.global_config.region' -r manifest.json", returnStdout: true).trim()
                org        = sh(script: "jq '.global_config.organization' -r manifest.json", returnStdout: true).trim()
                acme_email = sh(script: "jq '.cluster_config.certmanager_email_address' -r manifest.json", returnStdout: true).trim()
                build_tag  = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                veracode_api_id = sh(script: "aws secretsmanager get-secret-value --region $region --secret-id /$name/$env/veracode-secrets --query SecretString --output text | jq -r '.\"veracode-api-id\"'",
                                  returnStdout: true).trim()
                veracode_api_key = sh(script: "aws secretsmanager get-secret-value --region $region --secret-id /$name/$env/veracode-secrets --query SecretString --output text | jq -r '.\"veracode-api-key\"'",
                                  returnStdout: true).trim()
                ecr_repo_url   = sh(script: "aws secretsmanager get-secret-value --region $region --secret-id /$name/$env/ecr-repo/$image | jq -r '.SecretString'",
                                  returnStdout: true).trim()
                ecr_password   = sh(script: "aws ecr get-login-password --region $region", returnStdout: true).trim()
                ext_lb_dns     = sh(script: "aws elbv2 describe-load-balancers --names k3s-ext-lb-$env --region $region | jq -r '.LoadBalancers[].DNSName'",
                                  returnStdout: true).trim()
              sh """
                k3s_kubeconfig=/tmp/k3s_kubeconfig
                aws secretsmanager get-secret-value --secret-id k3s-kubeconfig-${name}-${env}-${org}-${env}-v2 --region $region | jq -r '.SecretString' > \$k3s_kubeconfig
                export KUBECONFIG=\$k3s_kubeconfig
                """
            }
          }
        }
      }

    stage("Create Service Now Change Request") {
        steps {
          script {
            dir("${repoFolder}") {
            change_sys_id = snow.changeRequest("DevOps $image build ${buildNumber}: building and deploying $image to $env kubernetes cluster in region $region", "$image is currently being built and deployed by jenkins to $env kubernetes cluster in region $region, Link to build: ${buildUrl}", "DevOps build ${buildNumber} has started, Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", null, null, null, null, null, null)
          }
        }
      }
    }

    stage("Veracode Static Code Analysis") {
        steps {
          script {
            try {
              dir("${projectDir}/microservices/$image") {
              snow.workNote("Zipping $image application and uploading to veracode for running software composition and static code analysis.", "${change_sys_id[0]}")
              sh """
              zip -r app.zip app
              """
              veracode applicationName: "${image}", timeout: 8, createProfile: true, criticality: "Medium", debug: true, waitForScan: true, deleteIncompleteScanLevel: "2", scanName: "${image}-build-${buildNumber}", uploadIncludesPattern: 'app.zip', vid: "${veracode_api_id}", vkey: "${veracode_api_key}"
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to run veracode analysis on $image pipeline", "Stage Veracode Static Code Analysis failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
          }
        }
      }

    stage("Evaluate Veracode Findings") {
        steps {
          script {
            try {
              dir("${projectDir}/python") {
              snow.workNote("Evaluating veracode findings for $image application.", "${change_sys_id[0]}")
              sh """
              python3 -m venv ./venv
              pip3 install -r requirements.txt
              mkdir -p ~/.veracode
              rm -rf ~/.veracode/credentials && touch ~/.veracode/credentials
              echo "[default]" >> ~/.veracode/credentials
              echo "veracode_api_key_id = $veracode_api_id" >> ~/.veracode/credentials
              echo "veracode_api_key_secret = $veracode_api_key" >> ~/.veracode/credentials
              """
              results = sh(script: "python3 ./veracode.py $image", returnStdout: true).trim()
              compliance_status = readJSON(text: results).COMPLIANCE_STATUS
              analysis_score = readJSON(text: results).ANALYSIS_SCORE
              analysis_rating = readJSON(text: results).ANALYSIS_RATING
              low = readJSON(text: results).LOW
              medium = readJSON(text: results).MEDIUM
              high = readJSON(text: results).HIGH
              critical = readJSON(text: results).CRITICAL
              policy_name = readJSON(text: results).POLICY_NAME
                if (compliance_status != "Pass") {
                  incident_sys_id = snow.incident("DevOps $image veracode scan ${buildNumber}: SAST/SCA compliance failed, please remediate findings", "Policy Name: $policy_name, Compliance Status: $compliance_status, Analysis Score: $analysis_score, Analysis Rating: $analysis_rating. Please review findings in veracode web ui https://web.analysiscenter.veracode.com/", "$image contains $critical critical findings, $high high findings, $medium medium findings and $low low findings", "${change_sys_id[0]}", null, null, null)
                  snow.workNote("Veracode failed compliance check for $image: created incident ${incident_sys_id}, please remediate findings.", "${change_sys_id[0]}")
                  throw new Exception("Compliance check failed for $image, please review findings and remediate")
                }
                else if (compliance_status == "Pass") {
                  snow.workNote("Veracode passed compliance checks, results for $image: Compliance Status: $compliance_status, Analysis Score: $analysis_score, Analysis Rating: $analysis_rating", "${change_sys_id[0]}")
                }
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to evaluate veracode findings on $image pipeline", "Stage Evaluate Veracode Findings failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
          }
        }
      }
    
      stage("Build Image") {
        steps {
          script {
            try {
            dir("${projectDir}/microservices/$image") {
                snow.workNote("Building docker image with tags: $ecr_repo_url:$buildNumber, $ecr_repo_url:$build_tag, $ecr_repo_url:$branch", "${change_sys_id[0]}")
                sh """
                docker build -t $ecr_repo_url:$buildNumber -t $ecr_repo_url:$build_tag -t $ecr_repo_url:$branch .
                """
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to build image on $image pipeline", "Stage Build Image failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
        }
      }
    }
    
      stage("Push Image to ECR") {
        steps {
          script {
            try {
            dir("${projectDir}/microservices/$image") {
                snow.workNote("Pushing $image build image to ecr $ecr_repo_url", "${change_sys_id[0]}")
                sh """
                docker login --password $ecr_password --username AWS $ecr_repo_url
                docker image push --all-tags $ecr_repo_url
                """
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to push build image to ecr on $image pipeline", "Stage Push Image to ECR failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
        }
      }
    }

      stage("Prepare Kubernetes Namespace") {
        steps {
          script {
            try {
            dir("${projectDir}") {
              snow.workNote("Preparing kubernetes namespace and creating secrets for $image on $env cluster in region $region", "${change_sys_id[0]}")
              sh """
              kubectl create namespace $image --dry-run=client -o yaml | kubectl apply -f -
              kubectl create secret -n $image docker-registry regcred --docker-server=$ecr_repo_url --docker-username=AWS --docker-password=$ecr_password --docker-email=$acme_email --dry-run=client -o yaml | kubectl apply -f -
              """
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to prepare kubernetes namespace on $image pipeline", "Stage Prepare Kubernetes Namespace failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
        }
      }
    }

      stage("Generate Kubernetes manifests") {
        steps {
          script {
            try {
            dir("${projectDir}") {
              snow.workNote("Generating kubernetes manifests for $image on $env cluster in region $region", "${change_sys_id[0]}")
              sh """
              make -f pipelines-as-code/jenkins/Makefile generate-manifests \
                      serviceName=$image \
                      environment=$env \
                      portNumber=8080 \
                      imageName=$ecr_repo_url \
                      imageTag=$build_tag \
                      nameSpace=$image \
                      pathPrefix="/$image" \
                      repoFolder=${projectDir}
              """
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to genearate kubernetes manifests on $image pipeline", "Stage Generate Kubernetes Manifests failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
        }
      }
    }
  
      stage("Deploy Manifests") {
        steps {
          script {
            try {
            dir("${projectDir}") {
              snow.workNote("Deploying kubernetes manifests for $image on $env cluster in region $region", "${change_sys_id[0]}")
              sh """
              kubectl apply -f ${image}.yaml
              kubectl apply -f ingress.yaml
              """
              }
            }
            catch (Exception e) {
              echo "Exception occured: " + e.toString()
              problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed to deploy kubernetes manifests on $image pipeline", "Stage Deploy Kubernetes Manifests failed to run, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
              snow.updateChange("failure", "${change_sys_id[0]}")
              error(e.toString())
            }
        }
      }
    }

    stage("Healthcheck") {
      steps {
        script {
          try {
          dir("${projectDir}") {
            snow.workNote("Performing healthcheck against $image endpoint http://${ext_lb_dns}/${image}/ on $env cluster in region $region", "${change_sys_id[0]}")
            sh """
              bash -c 'while [[ "\$(curl -s -o /dev/null -w ''%{http_code}'' http://${ext_lb_dns}/${image}/)" != "200" ]]; do echo "waiting for $image healtheck to pass, sleeping.";\\sleep 5; done; echo "$image url: http://${ext_lb_dns}/${image}/"'
            """
            snow.updateChange("success", "${change_sys_id[0]}")
            }
          }
          catch (Exception e) {
            echo "Exception occured: " + e.toString()
            problem_sys_id = snow.problem("DevOps $image build ${buildNumber}: Failed healthcheck for $image application, endpoint url is http://${ext_lb_dns}/${image}/", "Stage Healthcheck failed, the error was ${e.toString()}. Link to build: ${buildUrl}, Commit Hash: ${build_tag}, Application: ${image}, Environment: ${env}, Region: ${region}", "${change_sys_id[0]}")
            snow.updateChange("failure", "${change_sys_id[0]}")
            error(e.toString())
          }
        }
      }
    }

    stage("Clean Workspace") {
        steps {
          script {
            cleanWs()
            sh """
            docker rmi -f \$(docker images -q $ecr_repo_url:*)
            """
        }
      }
    }
  }
}