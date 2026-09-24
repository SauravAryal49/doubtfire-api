// OnTrack (Doubtfire API) - Jenkins CI/CD pipeline
// Stages: Build -> Test -> Code Quality -> Security -> Deploy (staging)
//         -> Release (production) -> Monitoring
//
// Every stage after Build uses the SAME Docker image (build once, promote).
// Feature branches stop after staging; only 'main' goes to production.

pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    timeout(time: 120, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    disableConcurrentBuilds()
  }

  parameters {
    choice(name: 'SIMULATE_INCIDENT', choices: ['none', 'outage', 'load', 'cpu'],
           description: 'After release, trigger a real incident to prove alerting works')
    booleanParam(name: 'SECURITY_GATE', defaultValue: true,
                 description: 'Fail the build on unresolved critical security findings')
  }

  environment {
    REGISTRY       = 'localhost:5000'
    IMAGE_NAME     = "${REGISTRY}/ontrack-api"
    APP_VERSION    = "1.0.${BUILD_NUMBER}"
    COMPOSE_DOCKER_CLI_BUILD = '1'
    DOCKER_BUILDKIT = '1'
  }

  stages {

    stage('Checkout & Version') {
      steps {
        script {
          env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.BRANCH_SAFE = (env.BRANCH_NAME ?: 'main').replaceAll('[^A-Za-z0-9_.-]', '-')
          env.IMAGE_TAG = "${env.APP_VERSION}-${env.GIT_SHORT}"
          currentBuild.displayName = "#${BUILD_NUMBER} v${APP_VERSION} (${env.BRANCH_SAFE}@${env.GIT_SHORT})"
          currentBuild.description = "Image ${IMAGE_NAME}:${env.IMAGE_TAG}"
        }
        sh 'rm -rf reports && mkdir -p reports'
      }
    }

    stage('Build') {
      steps {
        sh '''
          echo "==> Building ${IMAGE_NAME}:${IMAGE_TAG}"
          docker build \
            --label org.opencontainers.image.title="OnTrack API" \
            --label org.opencontainers.image.version="${APP_VERSION}" \
            --label org.opencontainers.image.revision="${GIT_COMMIT}" \
            --label org.opencontainers.image.source="${GIT_URL}" \
            --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --label ci.build.url="${BUILD_URL}" \
            -t "${IMAGE_NAME}:${IMAGE_TAG}" \
            -t "${IMAGE_NAME}:${BRANCH_SAFE}-latest" \
            .

          echo "==> Pushing to registry ${REGISTRY}"
          docker push "${IMAGE_NAME}:${IMAGE_TAG}"
          docker push "${IMAGE_NAME}:${BRANCH_SAFE}-latest"

          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE_NAME}:${IMAGE_TAG}")
          SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE_NAME}:${IMAGE_TAG}")
          cat > build-info.json <<EOF
{
  "version": "${APP_VERSION}",
  "image": "${IMAGE_NAME}:${IMAGE_TAG}",
  "digest": "${DIGEST}",
  "size_bytes": ${SIZE},
  "branch": "${BRANCH_SAFE}",
  "commit": "${GIT_COMMIT}",
  "build_url": "${BUILD_URL}",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
          cat build-info.json
        '''
        archiveArtifacts artifacts: 'build-info.json, Gemfile.lock', fingerprint: true
      }
    }

    stage('Test') {
      parallel {
        stage('Unit tests') {
          steps {
            sh 'bash ci/scripts/run-tests.sh unit "test/models test/mailers test/sidekiq test/config test/channels"'
          }
        }
        stage('Integration tests') {
          steps {
            sh 'bash ci/scripts/run-tests.sh integration "test/api"'
          }
        }
      }
      post {
        always {
          junit testResults: 'reports/*/junit/*.xml', allowEmptyResults: false
          sh 'bash ci/scripts/merge-coverage.sh || true'
          recordCoverage(
            tools: [[parser: 'COBERTURA', pattern: 'reports/coverage/coverage.xml']],
            id: 'coverage', name: 'OnTrack coverage',
            sourceCodeRetention: 'LAST_BUILD',
            qualityGates: [[threshold: 68.0, metric: 'LINE', baseline: 'PROJECT', criticality: 'FAILURE']]
          )
          archiveArtifacts artifacts: 'reports/coverage/**', allowEmptyArchive: true
        }
      }
    }

    stage('Code Quality') {
      steps {
        sh '''
          mkdir -p reports/quality
          NAME="ontrack-rubocop-${BUILD_NUMBER}"
          docker rm -f "$NAME" >/dev/null 2>&1 || true
          docker run --name "$NAME" --entrypoint "" "${IMAGE_NAME}:${IMAGE_TAG}" \
            bash -c "bundle exec rubocop --format json --out /tmp/rubocop.json --format progress --out /tmp/rubocop.txt; exit 0"
          docker cp "$NAME:/tmp/rubocop.json" reports/quality/rubocop.json
          docker cp "$NAME:/tmp/rubocop.txt"  reports/quality/rubocop.txt
          docker rm -f "$NAME" >/dev/null
          echo "RuboCop offenses: $(jq '.summary.offense_count' reports/quality/rubocop.json)"
        '''
        withSonarQubeEnv('SonarQube') {
          sh '''
            sonar-scanner \
              -Dsonar.projectVersion="${APP_VERSION}" \
              -Dsonar.scm.revision="${GIT_COMMIT}"
          '''
        }
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
      post {
        always {
          recordIssues(
            id: 'rubocop', name: 'RuboCop',
            tools: [ruboCop(pattern: 'reports/quality/rubocop.txt')],
            qualityGates: [[threshold: 1, type: 'NEW', criticality: 'UNSTABLE']]
          )
        }
      }
    }

    stage('Security') {
      environment {
        SECURITY_GATE = "${params.SECURITY_GATE}"
      }
      steps {
        sh 'bash ci/scripts/security-scan.sh'
      }
      post {
        always {
          recordIssues(
            id: 'security', name: 'Security',
            enabledForFailure: true,
            tools: [
              brakeman(pattern: 'reports/security/brakeman.json'),
              trivy(pattern: 'reports/security/trivy-image.json'),
              sarif(id: 'gitleaks', name: 'Gitleaks', pattern: 'reports/security/gitleaks.sarif')
            ]
          )
          archiveArtifacts artifacts: 'reports/security/**', allowEmptyArchive: true
        }
      }
    }

    stage('Deploy to Staging') {
      steps {
        withCredentials([file(credentialsId: 'ontrack-staging-secrets', variable: 'SECRETS_FILE')]) {
          script {
            try {
              sh 'bash ci/scripts/deploy.sh staging "${IMAGE_NAME}:${IMAGE_TAG}"'
              sh 'bash ci/scripts/smoke.sh staging all'
            } catch (err) {
              echo "Staging verification failed - rolling back: ${err}"
              sh 'bash ci/scripts/deploy.sh staging --rollback || echo "no previous staging version"'
              throw err
            }
          }
        }
      }
      post {
        always {
          junit testResults: 'reports/newman-staging.xml', allowEmptyResults: true
        }
      }
    }

    stage('Release to Production') {
      when { branch 'main' }
      steps {
        sh '''
          echo "==> Promoting ${IMAGE_NAME}:${IMAGE_TAG} -> ${APP_VERSION}, prod"
          docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:${APP_VERSION}"
          docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${IMAGE_NAME}:prod"
          docker push "${IMAGE_NAME}:${APP_VERSION}"
          docker push "${IMAGE_NAME}:prod"
        '''
        withCredentials([file(credentialsId: 'ontrack-prod-secrets', variable: 'SECRETS_FILE')]) {
          script {
            try {
              sh 'bash ci/scripts/deploy.sh production "${IMAGE_NAME}:${APP_VERSION}"'
              sh 'bash ci/scripts/smoke.sh production Smoke'
            } catch (err) {
              echo "Production verification failed - rolling back: ${err}"
              sh 'bash ci/scripts/deploy.sh production --rollback || echo "no previous production version"'
              throw err
            }
          }
        }
        withCredentials([usernamePassword(credentialsId: 'github-pat',
                                          usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          sh 'bash ci/scripts/github-release.sh'
        }
      }
      post {
        always {
          junit testResults: 'reports/newman-production.xml', allowEmptyResults: true
        }
      }
    }

    stage('Monitoring') {
      when { branch 'main' }
      steps {
        withCredentials([
          string(credentialsId: 'discord-webhook', variable: 'DISCORD_WEBHOOK_URL'),
          string(credentialsId: 'grafana-admin-password', variable: 'GF_ADMIN_PASSWORD')
        ]) {
          sh 'docker compose -f ci/monitoring/docker-compose.yml up -d --build --wait'
          sh 'bash ci/scripts/verify-monitoring.sh'
          script {
            if (params.SIMULATE_INCIDENT != 'none') {
              sh "bash ci/scripts/simulate-incident.sh ${params.SIMULATE_INCIDENT}"
            }
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/monitoring/**', allowEmptyArchive: true
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/*.txt', allowEmptyArchive: true
    }
    success {
      withCredentials([string(credentialsId: 'discord-webhook', variable: 'DISCORD_WEBHOOK_URL')]) {
        sh 'bash ci/scripts/notify.sh SUCCESS'
      }
    }
    failure {
      withCredentials([string(credentialsId: 'discord-webhook', variable: 'DISCORD_WEBHOOK_URL')]) {
        sh 'bash ci/scripts/notify.sh FAILURE'
      }
    }
    cleanup {
      sh 'docker image prune -f >/dev/null 2>&1 || true'
    }
  }
}
