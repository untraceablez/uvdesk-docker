// Jenkinsfile - automated multi-arch UVdesk image builds.
// Flow: Resolve release -> Quality gate -> Fetch source -> Build & Publish -> (notify on failure)
// Governed by .specify/memory/constitution.md (Principles I-V).
//
// Split agents:
//   * Most stages run on the `unraid-docker` permanent node (label `docker`) — a
//     REAL Docker daemon is required for buildx multi-arch + QEMU + docker run,
//     which the daemonless kaniko agents cannot do.
//   * The Quality gate runs IN-CLUSTER on the `sonar` pod (sonar-scanner-cli),
//     reaching SonarQube over the internal service URL — the off-cluster VM
//     cannot pass the Cloudflare Access edge in front of the public URL.

pipeline {
  agent { label 'docker' }

  options {
    // Principle IV: single-flight so overlapping poll cycles cannot corrupt tags.
    disableConcurrentBuilds()
    timeout(time: 90, unit: 'MINUTES')
    // (No timestamps() — the Timestamper plugin is not installed on this controller.)
  }

  // FR-009: poll the upstream releases on a schedule (default hourly).
  triggers {
    cron(env.POLL_SCHEDULE ?: 'H * * * *')
  }

  parameters {
    string(name: 'VERSION', defaultValue: '',
           description: 'Optional exact upstream version (e.g. 1.1.8). Empty = auto-select newest eligible.')
    booleanParam(name: 'FORCE_REBUILD', defaultValue: false,
           description: 'Rebuild & republish even if already published on both registries.')
  }

  environment {
    // Image identity / registries (set as Jenkins global/folder env properties).
    IMAGE_NAME          = "${env.IMAGE_NAME ?: 'uvdesk'}"
    DOCKERHUB_NAMESPACE = "${env.DOCKERHUB_NAMESPACE ?: ''}"
    GHCR_OWNER          = "${env.GHCR_OWNER ?: 'untraceablez'}"
    WORK_DIR            = '.work'

    // usernamePassword credentials -> _USR / _PSW (defined in JCasC).
    DOCKERHUB_CREDS = credentials('dockerhub-token')
    GHCR_CREDS      = credentials('ghcr-token')

    NOTIFY_EMAIL = "${env.NOTIFY_EMAIL ?: 'taylorcohrontech@gmail.com'}"
  }

  stages {
    stage('Prepare builder') {
      steps {
        sh '''
          set -eu
          docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
          docker buildx inspect uvdesk-builder >/dev/null 2>&1 || docker buildx create --name uvdesk-builder --use
          docker buildx use uvdesk-builder
          docker buildx inspect --bootstrap >/dev/null
        '''
      }
    }

    stage('Registry login') {
      steps {
        sh '''
          set -eu
          echo "$DOCKERHUB_CREDS_PSW" | docker login docker.io -u "$DOCKERHUB_CREDS_USR" --password-stdin
          echo "$GHCR_CREDS_PSW"      | docker login ghcr.io   -u "$GHCR_CREDS_USR"      --password-stdin
        '''
      }
    }

    stage('Resolve release') {
      steps {
        sh 'scripts/check-release.sh'
        script {
          // Read decision.env values with sandbox-safe steps only: sh(returnStdout)
          // + fixed env assignments (no readProperties/readFile, no dynamic env[...]
          // which the Groovy sandbox rejects as putAt).
          env.ACTION    = sh(returnStdout: true, script: '. .work/decision.env; printf %s "$ACTION"').trim()
          env.VERSION   = sh(returnStdout: true, script: '. .work/decision.env; printf %s "$VERSION"').trim()
          env.IS_NEWEST = sh(returnStdout: true, script: '. .work/decision.env; printf %s "$IS_NEWEST"').trim()
          echo "Decision: action=${env.ACTION} version=${env.VERSION} is_newest=${env.IS_NEWEST}"
        }
      }
    }

    stage('Quality gate') {
      when { expression { env.ACTION == 'build' } }
      // Run in-cluster: the sonar-scanner-cli pod reaches SonarQube on the internal
      // service URL (withSonarQubeEnv('SonarQube')), sidestepping Cloudflare Access.
      agent { label 'sonar' }
      steps {
        container('sonar-scanner') {
          withSonarQubeEnv('SonarQube') {
            sh 'scripts/quality-gate.sh'
          }
        }
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Fetch source') {
      when { expression { env.ACTION == 'build' } }
      steps {
        sh "IS_NEWEST=${env.IS_NEWEST} scripts/fetch-source.sh ${env.VERSION}"
      }
    }

    stage('Build & Publish') {
      when { expression { env.ACTION == 'build' } }
      steps {
        // Runs the upstream-integrity guard, then the atomic multi-arch build +
        // dual-registry publish + arch-pinned tags.
        sh 'scripts/build-and-push.sh'
      }
    }

    stage('Skipped (already published)') {
      when { expression { env.ACTION == 'skip' } }
      steps {
        echo "Version ${env.VERSION} already published on all registries — nothing to do (FR-010)."
      }
    }
  }

  post {
    failure {
      // Runs on the pipeline's default `docker` agent (workspace + scripts present).
      sh '''
        scripts/notify.sh "${VERSION:-unknown}" "${STAGE_NAME:-pipeline}" "${BUILD_URL:-n/a}" "See Jenkins log"
      '''
    }
    always {
      sh 'docker logout docker.io >/dev/null 2>&1 || true; docker logout ghcr.io >/dev/null 2>&1 || true'
    }
  }
}
