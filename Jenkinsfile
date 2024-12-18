pipeline {
    agent { 
        kubernetes { 
            label 'agent-runner' 
        } 
    }
    environment {
        // Docker image and GCR configuration
        MAIN_DOCKER_IMAGE_NAME = 'socialpost'
        GCS_NAMESPACE = 'socialpost'
        PROD_GCS_PROJECT_ID = 'socialpost-dev'
        PROD_CLUSTER_ID = 'gke-socialpost'
        PROD_REPOSITORY_NAME = 'asia.gcr.io/socialpost-dev'
        PROD_BRANCH_NAME = 'socialpost-dev-jenkins'

        // Staging configuration
        STAGE_GCS_PROJECT_ID = 'socialpost-dev'
        STAGE_CLUSTER_ID = 'gke-socialpost'
        STAGE_REPOSITORY_NAME = 'asia.gcr.io/socialpost-dev'
        STAGE_BRANCH_NAME = sh(script: 'echo "$GIT_BRANCH" | tr / -', returnStdout: true).trim().toLowerCase()

        // Git metadata
        GIT_SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
        GIT_COMMIT_MSG = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
    }
    stages {
        stage('Checkout') {
            steps {
                container('docker') {
                    checkout scm
                    sh 'echo ${GIT_BRANCH}'
                    slackSend channel: '#ci-cd-pipeline-alerts', 
                        color: '#36a64f', 
                        message: "Pipeline Started for `${MAIN_DOCKER_IMAGE_NAME}`\n`Branch`: *${GIT_BRANCH}*\n`Commit`: ${GIT_COMMIT_MSG}", 
                        teamDomain: 'your-slack-workspace', 
                        tokenCredentialId: 'slack-token'
                }
            }
        }

        // Build stage for both production and staging
        stage('Build Docker Image') {
            steps {
                container('docker') {
                    withCredentials([string(credentialsId: 'NEW_RELIC_LICENSE_KEY', variable: 'NEW_RELIC_LICENSE_KEY')]) {
                        script {
                            def targetRepo = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_REPOSITORY_NAME : STAGE_REPOSITORY_NAME
                            def tag = (GIT_BRANCH == PROD_BRANCH_NAME) ? GIT_SHORT_SHA : "${STAGE_BRANCH_NAME}:${GIT_SHORT_SHA}"
                            sh "docker build . -t ${targetRepo}/${MAIN_DOCKER_IMAGE_NAME}:${tag} --build-arg NEW_RELIC_LICENSE_KEY=${NEW_RELIC_LICENSE_KEY}"
                        }
                    }
                }
            }
        }

        // Push image to GCR
        stage('Push to GCR') {
            steps {
                container('gcp-sdk') {
                    withCredentials([file(credentialsId: 'docker-push-key', variable: 'GCS_DOCKER_KEY')]) {
                        sh 'cat ${GCS_DOCKER_KEY} > key.json'
                        sh 'docker login -u _json_key --password-stdin https://asia.gcr.io < key.json'
                        script {
                            def targetRepo = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_REPOSITORY_NAME : STAGE_REPOSITORY_NAME
                            def tag = (GIT_BRANCH == PROD_BRANCH_NAME) ? GIT_SHORT_SHA : "${STAGE_BRANCH_NAME}:${GIT_SHORT_SHA}"
                            sh "docker push ${targetRepo}/${MAIN_DOCKER_IMAGE_NAME}:${tag}"
                        }
                        sh 'docker logout'
                    }
                }
            }
        }

        // Deploy to Kubernetes cluster
        stage('Deploy to Kubernetes') {
            steps {
                container('gcp-sdk') {
                    withCredentials([file(credentialsId: 'k8s-key', variable: 'GCS_k8s_KEY')]) {
                        sh "gcloud auth activate-service-account --key-file=${GCS_k8s_KEY}"
                    }
                    script {
                        def targetCluster = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_CLUSTER_ID : STAGE_CLUSTER_ID
                        def targetProject = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_GCS_PROJECT_ID : STAGE_GCS_PROJECT_ID
                        def targetRepo = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_REPOSITORY_NAME : STAGE_REPOSITORY_NAME
                        def tag = (GIT_BRANCH == PROD_BRANCH_NAME) ? GIT_SHORT_SHA : "${STAGE_BRANCH_NAME}:${GIT_SHORT_SHA}"

                        sh "gcloud config set project ${targetProject}"
                        sh "gcloud config set container/cluster ${targetCluster}"
                        sh "gcloud config set compute/region asia-south1"
                        sh "gcloud container clusters get-credentials ${targetCluster} --region asia-south1 --project ${targetProject}"

                        sh "kubectl -n ${GCS_NAMESPACE} set image deployment/socialpost-deployment socialpost=${targetRepo}/${MAIN_DOCKER_IMAGE_NAME}:${tag}"
                        sh "gcloud auth revoke --all"
                    }
                }
            }
        }

        // Cleanup old Docker images
        stage('Docker Cleanup') {
            steps {
                container('docker') {
                    script {
                        def targetRepo = (GIT_BRANCH == PROD_BRANCH_NAME) ? PROD_REPOSITORY_NAME : STAGE_REPOSITORY_NAME
                        def tag = (GIT_BRANCH == PROD_BRANCH_NAME) ? GIT_SHORT_SHA : "${STAGE_BRANCH_NAME}:${GIT_SHORT_SHA}"

                        sh "docker rmi -f ${targetRepo}/${MAIN_DOCKER_IMAGE_NAME}:${tag}"
                        sh "docker system prune -f"
                    }
                }
            }
        }
    }
    post {
        always {
            cleanWs(
                cleanWhenNotBuilt: true,
                cleanWhenAborted: true,
                cleanWhenFailure: true,
                cleanWhenSuccess: true,
                cleanWhenUnstable: true,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
    }
}

