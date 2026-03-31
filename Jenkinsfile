pipeline {
    agent { label 'UbuntuAgent' }

    environment {
        IMAGE_NAME      = "portfolio-app"
        TEST_CONTAINER  = "portfolio-test"
        PROD_CONTAINER  = "portfolio-prod"
        TEST_PORT       = "8081"
        PROD_PORT       = "80"
        EMAIL_TO        = "iamakhilkt@gmail.com"
        APP_NAME        = "Portfolio App"
        TEAM_NAME       = "Akhil DevOps Team"
        DOCKERHUB_USER  = "akhilkt24"
        DOCKER_IMAGE    = "akhilkt24/portfolio-app"
        DOCKER_BUILDKIT = "1"
        TRIVY_CACHE     = "/tmp/trivy-cache"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
    }

    triggers {
        cron('H 2 * * *')
    }

    stages {

        stage('Checkout Code') {
            steps {
                echo "Pulling source code from GitHub..."
                git branch: 'main',
                    credentialsId: 'Git_cred',
                    url: 'https://github.com/akhilkt24/NewProject.git'
            }
        }

        stage('Pre Cleanup') {
            steps {
                echo "Cleaning system before build..."
                sh '''
                    docker system prune -af || true
                    rm -rf /home/akhilkt/.cache/* || true
                    rm -rf $TRIVY_CACHE || true
                    mkdir -p $TRIVY_CACHE
                '''
            }
        }

        stage('Save Rollback Version') {
            steps {
                echo "Saving current production image for rollback..."
                script {
                    def currentImage = sh(
                        script: "docker inspect --format='{{.Config.Image}}' portfolio-prod 2>/dev/null || echo 'none'",
                        returnStdout: true
                    ).trim()
                    env.ROLLBACK_IMAGE = currentImage
                    echo "Rollback version saved: ${env.ROLLBACK_IMAGE}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Building Docker image: $IMAGE_NAME:$BUILD_NUMBER"
                sh '''
                    docker build -t $IMAGE_NAME:$BUILD_NUMBER .
                    docker tag $IMAGE_NAME:$BUILD_NUMBER $IMAGE_NAME:latest
                '''
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                echo "Running Trivy security scan..."
                script {

                    def trivyCheck = sh(
                        script: "which trivy",
                        returnStatus: true
                    )
                    if (trivyCheck != 0) {
                        error "Trivy is NOT installed!"
                    }

                    def scanResult = sh(
                        script: """
                            trivy image \
                            --cache-dir $TRIVY_CACHE \
                            --exit-code 1 \
                            --severity CRITICAL \
                            --no-progress \
                            $IMAGE_NAME:$BUILD_NUMBER
                        """,
                        returnStatus: true
                    )

                    if (scanResult != 0) {
                        error "Security scan FAILED (CRITICAL vulnerabilities OR runtime issue)."
                    }

                    echo "Security scan PASSED"
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo "Pushing image to Docker Hub..."
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin

                        docker tag $IMAGE_NAME:$BUILD_NUMBER $DOCKER_IMAGE:$BUILD_NUMBER
                        docker tag $IMAGE_NAME:$BUILD_NUMBER $DOCKER_IMAGE:latest

                        docker push $DOCKER_IMAGE:$BUILD_NUMBER
                        docker push $DOCKER_IMAGE:latest
                    '''
                }
            }
        }

        stage('Deploy to Test') {
            steps {
                echo "Deploying to TEST..."
                sh '''
                    docker rm -f $TEST_CONTAINER || true

                    BLOCKING=$(docker ps -q --filter "publish=$TEST_PORT")
                    if [ -n "$BLOCKING" ]; then
                        docker rm -f $BLOCKING
                    fi

                    docker run -d \
                        --name $TEST_CONTAINER \
                        --restart unless-stopped \
                        -p $TEST_PORT:80 \
                        $IMAGE_NAME:$BUILD_NUMBER
                '''
            }
        }

        stage('Health Check - Test') {
            steps {
                echo "Checking TEST health..."
                script {
                    sleep 10
                    def retries = 5
                    def ok = false

                    for (int i = 1; i <= retries; i++) {
                        def status = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:$TEST_PORT",
                            returnStdout: true
                        ).trim()

                        echo "Attempt ${i}: HTTP ${status}"

                        if (status == "200") {
                            ok = true
                            break
                        }

                        sleep 5
                    }

                    if (!ok) {
                        error "Test deployment FAILED"
                    }
                }
            }
        }

        stage('Cleanup Test Container') {
            steps {
                sh 'docker rm -f $TEST_CONTAINER || true'
            }
        }

        stage('Manual Approval') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Deploy build #${BUILD_NUMBER} to PRODUCTION?",
                          ok: "Deploy"
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                echo "Deploying to PRODUCTION..."
                sh '''
                    docker rm -f $PROD_CONTAINER || true

                    BLOCKING=$(docker ps -q --filter "publish=$PROD_PORT")
                    if [ -n "$BLOCKING" ]; then
                        docker rm -f $BLOCKING
                    fi

                    docker run -d \
                        --name $PROD_CONTAINER \
                        --restart unless-stopped \
                        -p $PROD_PORT:80 \
                        $IMAGE_NAME:$BUILD_NUMBER
                '''
            }
        }

        stage('Health Check - Production') {
            steps {
                echo "Checking PRODUCTION health..."
                script {
                    sleep 10
                    def retries = 5
                    def ok = false

                    for (int i = 1; i <= retries; i++) {
                        def status = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:$PROD_PORT",
                            returnStdout: true
                        ).trim()

                        echo "Attempt ${i}: HTTP ${status}"

                        if (status == "200") {
                            ok = true
                            break
                        }

                        sleep 5
                    }

                    if (!ok) {
                        error "Production FAILED"
                    }
                }
            }
        }

    }

    post {

        always {
            echo "Cleaning up system..."
            sh '''
                docker image prune -f --filter "until=24h" || true
                docker logout || true
            '''
        }

        failure {
            script {
                echo "Handling failure + rollback..."

                if (env.ROLLBACK_IMAGE && env.ROLLBACK_IMAGE != 'none') {
                    sh """
                        docker rm -f $PROD_CONTAINER || true

                        docker run -d \
                            --name $PROD_CONTAINER \
                            --restart unless-stopped \
                            -p $PROD_PORT:80 \
                            ${env.ROLLBACK_IMAGE}
                    """
                    echo "Rollback completed"
                } else {
                    echo "No rollback image available"
                }
            }
        }

        success {
            echo "Deployment successful!"
        }
    }
}
