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
                echo "Building Docker image: portfolio-app:${BUILD_NUMBER}"
                sh '''
                    docker build -t $IMAGE_NAME:$BUILD_NUMBER .
                    docker tag $IMAGE_NAME:$BUILD_NUMBER $IMAGE_NAME:latest
                    echo "Build complete: $IMAGE_NAME:$BUILD_NUMBER"
                '''
            }
        }

        stage('Security Scan') {
            steps {
                echo "Scanning image for vulnerabilities with Trivy..."
                script {
                    def trivyCheck = sh(
                        script: "which trivy",
                        returnStatus: true
                    )
                    if (trivyCheck != 0) {
                        error "Trivy is NOT installed or not in PATH!"
                    }
                    def scanResult = sh(
                        script: "trivy image --exit-code 1 --severity CRITICAL --no-progress $IMAGE_NAME:$BUILD_NUMBER",
                        returnStatus: true
                    )
                    if (scanResult != 0) {
                        error "CRITICAL vulnerabilities found! Aborting pipeline."
                    }
                    echo "Security scan PASSED — image is clean."
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo "Pushing image to Docker Hub as akhilkt24/portfolio-app..."
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
                        echo "Pushed to Docker Hub successfully!"
                    '''
                }
            }
        }

        stage('Deploy to Test') {
            steps {
                echo "Deploying to TEST on port 8081..."
                sh '''
                    docker rm -f $TEST_CONTAINER || true

                    BLOCKING=$(docker ps -q --filter "publish=$TEST_PORT")
                    if [ -n "$BLOCKING" ]; then
                        echo "Removing container blocking port $TEST_PORT..."
                        docker rm -f $BLOCKING
                    fi

                    docker run -d \
                        --name $TEST_CONTAINER \
                        --restart unless-stopped \
                        --memory="256m" \
                        --cpus="0.5" \
                        -p $TEST_PORT:80 \
                        $IMAGE_NAME:$BUILD_NUMBER
                '''
            }
        }

        stage('Health Check - Test') {
            steps {
                echo "Running health check on TEST..."
                script {
                    sleep(time: 10, unit: 'SECONDS')
                    def retries = 5
                    def passed  = false

                    for (int i = 1; i <= retries; i++) {
                        def status = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:8081",
                            returnStdout: true
                        ).trim()
                        echo "Attempt ${i}/${retries} → HTTP ${status}"
                        if (status == "200") {
                            echo "Test health check PASSED!"
                            passed = true
                            break
                        }
                        if (i < retries) sleep(time: 5, unit: 'SECONDS')
                    }
                    if (!passed) {
                        error "Test health check FAILED after ${retries} attempts!"
                    }
                }
            }
        }

        stage('Cleanup Test Container') {
            steps {
                echo "Removing test container..."
                sh 'docker rm -f $TEST_CONTAINER || true'
            }
        }

        stage('Manual Approval') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Deploy build #${BUILD_NUMBER} to PRODUCTION?",
                          ok: "Deploy Now"
                }
            }
        }

        stage('Deploy to Production') {
            steps {
                echo "Deploying to PRODUCTION on port 80..."
                sh '''
                    docker rm -f $PROD_CONTAINER || true

                    BLOCKING=$(docker ps -q --filter "publish=$PROD_PORT")
                    if [ -n "$BLOCKING" ]; then
                        echo "Removing container blocking port $PROD_PORT..."
                        docker rm -f $BLOCKING
                    fi

                    docker run -d \
                        --name $PROD_CONTAINER \
                        --restart unless-stopped \
                        --memory="512m" \
                        --cpus="1.0" \
                        -p $PROD_PORT:80 \
                        $IMAGE_NAME:$BUILD_NUMBER
                '''
            }
        }

        stage('Health Check - Production') {
            steps {
                echo "Verifying PRODUCTION deployment..."
                script {
                    sleep(time: 10, unit: 'SECONDS')
                    def retries = 5
                    def passed  = false

                    for (int i = 1; i <= retries; i++) {
                        def status = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:80",
                            returnStdout: true
                        ).trim()
                        echo "Attempt ${i}/${retries} → HTTP ${status}"
                        if (status == "200") {
                            echo "Production is LIVE and healthy!"
                            passed = true
                            break
                        }
                        if (i < retries) sleep(time: 5, unit: 'SECONDS')
                    }
                    if (!passed) {
                        error "Production health check FAILED! Triggering rollback..."
                    }
                }
            }
        }

    }

    post {

        always {
            echo "Cleaning up dangling Docker images..."
            sh 'docker image prune -f --filter "until=24h" || true'
            sh 'docker logout || true'
        }

        failure {
            script {
                echo "Pipeline FAILED — checking rollback..."
                if (env.ROLLBACK_IMAGE && env.ROLLBACK_IMAGE != 'none') {
                    echo "Rolling back to: ${env.ROLLBACK_IMAGE}"
                    sh """
                        docker rm -f portfolio-prod || true

                        BLOCKING=\$(docker ps -q --filter "publish=80")
                        if [ -n "\$BLOCKING" ]; then
                            docker rm -f \$BLOCKING
                        fi

                        docker run -d \
                            --name portfolio-prod \
                            --restart unless-stopped \
                            --memory="512m" \
                            --cpus="1.0" \
                            -p 80:80 \
                            ${env.ROLLBACK_IMAGE}

                        echo "Rollback complete! Restored to ${env.ROLLBACK_IMAGE}"
                    """
                } else {
                    echo "No previous version found — skipping rollback."
                }

                mail to: "iamakhilkt@gmail.com",
                     mimeType: 'text/html',
                     subject: "FAILED [Portfolio App] Build #${BUILD_NUMBER} — Rolled Back",
                     body: """
                        <h2 style='color:red'>Build Failed</h2>
                        <p><b>App:</b> Portfolio App</p>
                        <p><b>Build:</b> #${BUILD_NUMBER}</p>
                        <p><b>Job:</b> ${JOB_NAME}</p>
                        <p><b>Rolled back to:</b> ${env.ROLLBACK_IMAGE ?: 'none'}</p>
                        <p><a href='${BUILD_URL}'>View Build Logs</a></p>
                        <p>— Akhil DevOps Team</p>
                     """
            }
        }

        success {
            mail to: "iamakhilkt@gmail.com",
                 mimeType: 'text/html',
                 subject: "SUCCESS [Portfolio App] Build #${BUILD_NUMBER} is LIVE",
                 body: """
                    <h2 style='color:green'>Deployment Successful</h2>
                    <p><b>App:</b> Portfolio App</p>
                    <p><b>Build:</b> #${BUILD_NUMBER}</p>
                    <p><b>Image:</b> akhilkt24/portfolio-app:${BUILD_NUMBER}</p>
                    <p><b>Live at:</b> http://YOUR_SERVER_IP</p>
                    <p><a href='${BUILD_URL}'>View Build Logs</a></p>
                    <p>— Akhil DevOps Team</p>
                 """
        }

        aborted {
            mail to: "iamakhilkt@gmail.com",
                 mimeType: 'text/html',
                 subject: "ABORTED [Portfolio App] Build #${BUILD_NUMBER}",
                 body: """
                    <h2 style='color:orange'>Build Aborted</h2>
                    <p><b>App:</b> Portfolio App</p>
                    <p><b>Build:</b> #${BUILD_NUMBER}</p>
                    <p><b>Job:</b> ${JOB_NAME}</p>
                    <p><a href='${BUILD_URL}'>View Build Logs</a></p>
                    <p>— Akhil DevOps Team</p>
                 """
        }

    }
}
