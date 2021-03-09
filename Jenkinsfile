/**
 * Helper function for looping over Map object
 *
 */
@NonCPS
def mapToList(depmap) {
    def dlist = []
    for (def entry in depmap) {
        dlist.add(new java.util.AbstractMap.SimpleImmutableEntry(entry.key, entry.value))
    }
    dlist
}

/**
 * Functions to validate image
 *
 */
def helmLint(Map args) {
    // lint helm chart
    sh "/usr/local/bin/helm lint ${args.chart_dir} --set build=${args.commit_id},image.repository=${args.repo},image.tag=${args.tag},version=${args.version},config.directory=config/${args.namespace},ingress.type=${INGRESS_VERSION}"
}

/**
 * Functions to deploy image
 *
 */
def helmDeploy(Map args) {
    try {

        // Configure helm client
        if (args.dry_run) {
            println "Running dry-run deployment"

            sh "/usr/local/bin/helm install --dry-run --debug ${args.name} ${args.chart_dir} --set build=${args.commit_id},image.repository=${args.repo},image.tag=${args.tag},version=${args.version},config.directory=config/${args.namespace},ingress.type=${INGRESS_VERSION} --namespace=${args.namespace}"
        } else {

            println "Running deployment"
            sh "/usr/local/bin/helm upgrade --install ${args.name} ${args.chart_dir} --set build=${args.commit_id},image.repository=${args.repo},image.tag=${args.tag},version=${args.version},config.directory=config/${args.namespace},ingress.type=${INGRESS_VERSION} --namespace=${args.namespace}"

            echo "Application ${args.name} successfully deployed. Use helm status ${args.name} to check."
        }
    }

    catch(exception) {

        // Slack notification failure.
        notifyBuild('FAILURE', null, null, "Error in pushing image to `${args.namespace}` Kubernetes.", args.notify, args.slack_channel)

        println "Error on Upgrade / Install"
    }
}

/**
 * Track Git logs
 *
 */
def showChangeLogs() {

    def authors       = []
    def accept        = []
    def changeLogSets = currentBuild.rawBuild.changeSets

    if (changeLogSets.size() == 0) return [];

    for (int i = 0; i < changeLogSets.size(); i++) {

        def entries = changeLogSets[i].items
        for (int j = 0; j < entries.length; j++) {

            def author = "${entries[j].author}"
            def email  = entries[j].author.getProperty(hudson.tasks.Mailer.UserProperty.class).getAddress()

            authors.push("${author}:${email}")

            def isParent   = false
            def source     = currentBuild.rawBuild.changeSets[i].browser.getChangeSetLink(entries[j]).toString().split('/')[4]
            def sourceDirs = []

            switch (source) {
                case 'intermx-pim-akeneo-helm':
                    accept.push(source)
                    isParent = true
                    break
                case 'intermx-cicd-helm':
                    sourceDirs = ['pim-service']
                    break
            }

            if (isParent) continue;

            def entry = entries[j]
            def files = new ArrayList(entry.affectedFiles)

            for (int k = 0; k < files.size(); k++) {

                !sourceDirs.contains(files[k].path.split('/')[0]) ?: accept.push(files[k].path)
            }
        }
    }

    return accept.unique().size() == 0 ?: authors.unique()
}

/**
 * Track Container Deployment Status
 *
 */
def getDeploymentStatus(commitId, environment) {
    sh "sleep 10s"

    def status
    def sleep   = ['ContainerCreating', 'Pending', 'Succeeded']
    def success = ['Running']
    def failure = ['CrashLoopBackOff', 'Terminating', 'Error']

    sh "kubectl get pods -l build=${commitId} --namespace=${environment} --sort-by=.status.startTime"

    def deploymentVerify = sh (script: "kubectl get pods -l build=${commitId} --namespace=${environment} --sort-by=.status.startTime | awk 'NR==2{print \$3}'", returnStdout: true).trim()
    def containerCount   = sh (script: "kubectl get pods -l build=${commitId} --namespace=${environment} --sort-by=.status.startTime | awk 'NR==2{print \$4}'", returnStdout: true).trim().toInteger()

    echo "Deployment Status: ${deploymentVerify}"
    echo "Container Restart Count: ${containerCount}"

    if (sleep.contains(deploymentVerify)) {
        return getDeploymentStatus(commitId, environment)
    }

    if (success.contains(deploymentVerify)) {
        if (containerCount == 0) {
            return true
        } else {
            return false
        }
    }

    if (failure.contains(deploymentVerify)) {
        return false
    }
}

/**
 * Jenkins pipeline stages.
 *
 * A list of stages available in this pipeline Jenkins file will be executed
 * squentially. The name of this file should be matching with Pipeline block of
 * Jenkins configuration.
 *
 */
node {

    /**
     * Version details for tagging the image.
     *
     * @var int major
     *   A current release major version number.
     * @var int minor
     *   A current release minor version number.
     * @var int patch
     *   A patch number for current release.
     *
     */
    // TODO: At present versioning is controlled by developer statically.
    // final major = "2020"
    // final minor = "05"
    // final patch = "22"

    // final tag = "v${major}.${minor}.${patch}_integration"

    def tag = "2021.01.12_staging"

    /**
     * Define script variables
     *
     */
    def notify
    def slackChannel = "#intermxapi"
    // Docker image
    def app
    // Config.json file
    def config
    // Component specific variables builds
    def component = "pim-service"
    def cluster
    def environment
    def chartDirectory
    // Config File from S3
    def configFile
    // Git Credentials
    def gitCredentials = "impinger-cicd-github"
    // Helm Repository
    def helmRepo = "git@github.com:InterMx/intermx-cicd-helm.git"
    // Helm Branch
    def helmBranch = 'delivery'
    // S3 Config Bucket
    def configBucket = "${AWS_BUCKET_NAME}"
    // AWS Account ID
    def awsAccountId = "${AWS_ACCOUNT_ID}"
    // AWS Credentials
    def awsCredentials = "intermx-impinger-credentials"
    // ECR Repository
    def ecrRepoName = "intermx-pim-service"
    // ECR Repository Endpoint
    def ecrEndpoint = "https://${awsAccountId}.dkr.ecr.us-east-1.amazonaws.com"
    // ECR FQDN
    def ecrRepoDns = "${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/${ecrRepoName}"
    // ECR Credentials
    def ecrCredentials = "ecr:us-east-1:${awsCredentials}"
    // Git commit message
    def commitMessage
    def commitId
    def deployment

    try {

        /**
         * Cloning the repository to workspace to build image.
         *
         */
        checkout scm

        // Get helm charts from git repo
        dir('helm') {
            git url: helmRepo, branch: helmBranch, credentialsId: gitCredentials, changelog: false, poll: false
        }

        def (origin, branch) = scm.branches[0].name.tokenize('/')

        commitMessage = sh (script: 'git log --oneline -1 ${GIT_COMMIT}', returnStdout: true).trim().substring(8)
        commitId      = sh (script: 'git log -1 --format=%H', returnStdout: true).trim() // %h, for short hash
        notify        = showChangeLogs()

        if (notify instanceof Boolean && Boolean.TRUE.equals(notify)) {

            return
        }

        // Slack notification in progress.
        notifyBuild('STARTED', branch, commitMessage)

        /**
         * Set Environment Variables.
         *
         */
        stage('Set Variables') {

            environment = 'development'
            cluster = 'delivery'
            sh "echo Development branch"
        }

        /**
         * Get dependencies for Kubernetes Deploy (Integration).
         *
         */
        stage('Get Dependencies for Integration') {

            // Download config.json from S3 into the insights-service/config helm repo
            final s3ConfigPath = "${cluster}/${environment}/${component}"

            chartDirectory = "helm/${component}"
            configFile     = "${chartDirectory}/config/${environment}/config.json"

            dir("${chartDirectory}/config/${environment}") {
                withAWS(credentials:awsCredentials) {
                    // s3Download(file: 'config.json', bucket: configBucket, path: "${s3ConfigPath}/config.json", force: true)
                    s3Download(file: 'filebeat.yaml', bucket: configBucket, path: "${s3ConfigPath}/filebeat.yaml", force: true)
                    s3Download(file: 'ilm_policy.json', bucket: configBucket, path: "${s3ConfigPath}/ilm_policy.json", force: true)
                }
            }

            dir("tls") {
                withAWS(credentials:awsCredentials) {
                    s3Download(file: 'apache-selfsigned.crt', bucket: configBucket, path: "${s3ConfigPath}/apache-selfsigned.crt", force: true)
                    s3Download(file: 'apache-selfsigned.key', bucket: configBucket, path: "${s3ConfigPath}/apache-selfsigned.key", force: true)
                    s3Download(file: 'dhparam.pem', bucket: configBucket, path: "${s3ConfigPath}/dhparam.pem", force: true)
                    s3Download(file: 'parameters.yml', bucket: configBucket, path: "${s3ConfigPath}/parameters.yml", force: true)
                }
            }
        }

        /**
         * Environment variables for Kubernetes (Integration).
         *
         */
        /* stage('Build Kubernetes Env Variables From Config for Integration') {

            config = readJSON file: "${configFile}"

            for (entry in mapToList(config)) {
                dir("${chartDirectory}/config"){
                    writeFile file: "${entry.key}", text: "${entry.value}"
                }
            }
        } */

        /**
         * Building the Docker image from cloned repository for Integration.
         *
         */
        stage('Build Image for Integration') {

            app = docker.build(ecrRepoName, "--build-arg env=${environment} --network host .")
        }

        /**
         * Authenticate and push the built image to AWS ECR for Integration.
         *
         */
        stage('Push Image for Integration') {

            docker.withRegistry(ecrEndpoint, ecrCredentials) {

                /**
                 * Push the built Image to AWS ECR for Integration.
                 *
                 */
                app.push(tag)
            }
        }

        /**
         * Deploy Image to Kubernetes using Helm for Integration.
         *
         */
        stage('Deploy Image for Integration') {

            // chartDirectory = "helm/kubernetes/insights/api-portal"

            // Run helm chart linter
            helmLint(
                chart_dir     : chartDirectory,
                chart_version : environment,
                tag           : tag,
                repo          : ecrRepoDns,
                name          : ecrRepoName,
                version       : environment,
                namespace     : environment,
                commit_id     : commitId
            )

            // Deploy using Helm chart
            helmDeploy(
                dry_run       : false,
                name          : ecrRepoName,
                repo          : ecrRepoDns,
                chart_dir     : chartDirectory,
                tag           : tag,
                version       : environment,
                namespace     : environment,
                notify        : notify,
                slack_channel : slackChannel,
                commit_id     : commitId
            )
        }

        /**
         * Track Container Status for Integration
         *
         */
        stage('Track Container Status for Integration') {
            // deployment = getDeploymentStatus(commitId, environment);

            // Slack notification success.
            /* if (deployment) {
                notifyBuild('SUCCESS', null, null, "Image deployed to `${environment}` Kubernetes successfully.")
            } else {
                notifyBuild('FAILURE', null, null, "Error in creating container, please check the code for ${environment}", notify, slackChannel)

                error ("Error in creating container, please check the code for ${environment}")
            } */

            notifyBuild('SUCCESS', null, null, "Image deployed to `${environment}` Kubernetes successfully.")
        }
    }

    catch(exception) {

        echo "${exception}"

        // Slack notification failure.
        notifyBuild('FAILURE', null, null, 'Something went wrong in one of the stages, exception found in Jenkins.', notify, slackChannel)
    }

    finally {

        // Clean up the workspace after finish the job.
        deleteDir()
    }
}

/**
 * Sending notifications to Slack channel.
 *
 */
def notifyBuild(buildStatus = 'FAILURE', branch = null, commitMessage = null, message = null, notify = null, channel = null) {
return
    // Default values
    def summary
    def alert   = false
    def org     = "${ORGANIZATION}"
    def baseURL = "${SLACK_BASE_URL}"

    org = org.toUpperCase()

    if (buildStatus == 'STARTED') {
        color = 'YELLOW'
        colorCode = '#FFFF00'
        summary = "${buildStatus}: ${org} - Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' is currently working on branch '${branch}' with a message: '${commitMessage}'"
    } else if (buildStatus == 'SUCCESS') {
        color = 'GREEN'
        colorCode = '#00FF00'
        summary = "${buildStatus}: ${org} - Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' | Message: ${message}"
    } else {
        color = 'RED'
        colorCode = '#FF0000'
        summary = "${buildStatus}: ${org} - Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' | Error: ${message} | URL: `${env.BUILD_URL}console` (please make sure, you are on VPN to access the Jenkins link)"
        alert = true
    }

    // Send notifications to Slack.
    slackSend (baseUrl: baseURL, color: colorCode, message: summary)

    if (alert) {
        for(int i = 0; i < notify.size(); i++) {
            def notice = notify[i].split(":")
            def author = notice[0]
            def email  = notice[1]
            def domain = email.split("@")[1]

            if (domain && domain == 'intermx.com') {

                emailext (
                    to: "${email}",
                    subject: "${buildStatus}: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: """
                      <html>
                        <body>
                          <p>Hi ${author},</p>
                          <br>
                          <p>The build job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' failed to complete.</p>
                          <p>The following error was reported:</p>
                          <br>
                          <p>${message}</p>
                          <br>
                          <p>Please review the error at <a href=\"${env.BUILD_URL}console\">${env.BUILD_URL}console</a> and resolve the issue causing the failure so that releases can continue.</p>
                        </body>
                      </html>
                    """
                )
            }
        }

        slackSend (baseUrl: baseURL, channel: "${channel}", color: colorCode, message: summary)
    }
}
