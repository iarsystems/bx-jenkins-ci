# IAR Build Tools in a Jenkins CI

> __Disclaimer__
> The information provided in this tutorial is subject to change without notice and does not represent a commitment on any part of IAR. While the information contained herein is useful as reference for DevOps Engineers willing to implement CI/CD using IAR Tools, IAR assumes no responsibility for any errors, omissions or particular implementations.

## Introduction
The [IAR Build Tools](https://iar.com/bx) comes with everything you need to build projects created with the IAR Embedded Workbench from the command line. [Jenkins][url-jenkins] is an automation controller suitable for CI (Continuous Integration). [Gitea][url-gitea] is a lightweight Git server. 

This tutorial provides a quick method for bootstrapping the IAR Build Tools, Gitea and Jenkins, each one on its own container, for building and analyzing your embedded projects on-premises. From this starting point, you can apply customizations suitable for your organization's needs.

![bx-jenkins-ci](https://github.com/IARSystems/bx-jenkins-ci/assets/54443595/facfe441-ebd4-4ea4-b079-9273b21be248)

## Pre-requisites
For completing this tutorial you are going to need to have the [__bx-docker__][url-bx-docker] tutorial completed. 

You will also need a web browser to access webpages. For this tutorial we will consider that the web browser is installed on a Windows machine in which you have privileges to execute administrative tasks and that can reach the Linux server containing the Docker daemon with the IAR Build Tools.

In the Linux server's shell, clone this repository to the user's home directory (`~`):
```
git clone https://github.com/iarsystems/bx-jenkins-ci.git ~/bx-jenkins-ci
```

<img alt="Docker" align="right" src="https://avatars.githubusercontent.com/u/5429470?s=96&v=4" /><br>

## Setting up a Docker Network
For simplifying this setup let's create a [docker network][url-docker-docs-net] named __jenkins__ in the Linux server's shell:
```
docker network create jenkins
```
From here onwards, we spawn all the tutorial's containers with `--network-alias <name> --network jenkins` so that they become visible and reacheable from each other.

As administrator, edit the __%WINDIR%/system32/drivers/etc/hosts__ file in the Windows PC. Add the following line, replacing `192.168.1.2` by the actual Linux server's IP address. With that, the Windows PC can reach the containers' exposed service ports by their respective network-alias names:
```
192.168.1.2 docker gitea jenkins
```

<img alt="IAR" align="right" src="https://avatars.githubusercontent.com/u/64431848?s=110&v=4" /><br>

## Setting up the IAR Build Tools
Now go back to the Linux server's shell to prepare the first container. The __jenkins-docker__ container will be based on the __docker:dind__ image, which provides a secure [Docker Registry][url-docker-registry] serving the Docker network you just created.

```
docker run --name jenkins-docker \
  --network jenkins --network-alias docker \
  --detach --restart unless-stopped --privileged \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 3001:3001 --publish 2376:2376 \
  docker:dind --storage-driver overlay2 
```

The Docker image with the IAR Build Tools created during the [bx-docker][url-bx-docker] tutorial can be loaded into this registry, becoming available for running containers for build jobs (the entire process might take a while):
```
export BX_IMAGE=$(docker image list -q --format="{{.Repository}}:{{.Tag}}" --filter="reference=iarsystems/bx*")
export BX_FILE=$(echo ${BX_IMAGE//:/-} | cut -f2 -d/)
docker save $BX_IMAGE | gzip > ~/$BX_FILE.tgz
docker cp ~/$BX_FILE.tgz jenkins-docker:/
rm ~/$BX_FILE.tgz
docker exec jenkins-docker docker load -i /$BX_FILE.tgz
docker exec jenkins-docker docker image list
docker exec jenkins-docker rm /$BX_FILE.tgz
export -n BX_FILE
```

> [!NOTE]
> The above __BX_IMAGE__ command automatically detects the IAR Build Tools image, assuming you currently only have one image.

The previous command sequence should provide an output showing the `docker image list` from the __jenkins-docker__ container:
>```
>Successfully copied 985MB to jenkins-docker:/
>Loaded image: iarsystems/bxarm:9.50.1
>REPOSITORY         TAG       IMAGE ID       CREATED         SIZE
>iarsystems/bxarm   9.50.1    bab152fb558d   7 minutes ago   3.73GB
>```

### Setup the license
This section must be performed once to setup the IAR Build Tools for making use of licenses from your network's IAR License Server.

Execute an interactive shell in the __jenkins-docker__ container:
```
docker exec -it jenkins-docker sh
```
Replace `IAR_LICENSE_SERVER_IP` by its actual IP address and, inside the __jenkins-docker__ container execute:
```
export IAR_LICENSE_SERVER_IP=192.168.1.3
export BX_IMAGE=$(docker image list -q --format="{{.Repository}}:{{.Tag}}" --filter="reference=iarsystems/bx*")
export LLM=$(docker run --rm $BX_IMAGE find /opt -type f -name "lightlicensemanager")
docker run --rm -v LMS2:/usr/local/etc/IARSystems $BX_IMAGE $LLM setup -s $IAR_LICENSE_SERVER_IP
export -n LLM BX_IMAGE IAR_LICENSE_SERVER_IP
exit
```

Back to the Linux server's shell, test the IAR C/C++ Compiler (`icc<target>`):
```
export BX_IMAGE=$(docker image list -q --format="{{.Repository}}:{{.Tag}}" --filter="reference=iarsystems/bx*")
COMPILER=$(docker exec jenkins-docker docker run $BX_IMAGE /usr/bin/find /opt -type f -wholename "*/bin/icc*")
docker exec jenkins-docker docker run --rm -v LMS2:/usr/local/etc/IARSystems $BX_IMAGE $COMPILER --version
```
Expect an output similar to:
>```
>IAR ANSI C/C++ Compiler VX.yy.zz/LNX for <target> BX
>```

Finally commit the changes to the __jenkins-docker__ container:
```
docker commit jenkins-docker
```

<img alt="Gitea" align="right" src="https://avatars.githubusercontent.com/u/12724356?s=84&v=4"/><br>


## Setting up Gitea
Now it is __gitea__ time. On the Linux server's shell, execute:
```
docker run --name gitea \
  --network jenkins --network-alias gitea \
  --detach --restart=unless-stopped \
  --volume gitea:/data \
  --volume /etc/timezone:/etc/timezone:ro \
  --volume /etc/localtime:/etc/localtime:ro \
  --publish 3000:3000 --publish 2222:2222 \
  gitea/gitea:1.20
```

A webhook is a mechanism which can be used to trigger associated build jobs in Jenkins whenever, for example, code is pushed into a Git repository.

Update `/data/gitea/conf/app.ini` for accepting webhooks from the __jenkins__ container, commit and restart:
```
docker exec gitea bash -c "echo -e '\n[webhook]\nALLOWED_HOST_LIST=jenkins\nDISABLE_WEBHOOKS=false' >> /data/gitea/conf/app.ini"
docker commit gitea
docker restart gitea
```

On the web browser, navigate to http://gitea:3000 to perform the initial Gitea setup:
- Make sure __Server Domain__ is set to `gitea`.
- Make sure __Gitea Base URL__ is set to `http://gitea:3000`. 
- Click __`Install Gitea`__.
- __Register__ a new user (http://gitea:3000/user/sign_up, suggestion: `jenkins`). The first user created is the administrator.

### Generating an access token
Instead of using the Gitea administrator account credentials outside its container, it is recommended to use a personal access token so that jenkins can access the repository without the need of using Gitea's administrative credentials.

To generate a new token in the user profile settings:
- Go to __Application__ → __Generate New Token__.
- Choose a __Token Name__ (e.g. "Jenkins Token").
- Select the following permissions:
   - __issue__: `Read and Write`
   - __notification__: `Read and Write`
   - __organization__: `Read and Write`
   - __repository__: `Read and Write`
   - __user__: `Read and Write`
- click on __Generate Token__.

> [!TIP]
> You can generate as many access tokens as you need however, when generating a new token, make sure to copy it when shown in the next page. It will never be shown again.

### Example by migrating an existing repository
On the top-right corner of the page:
- Go to __`+`__ → __New Migration__ → __GitHub__ (http://gitea:3000/repo/migrate?service_type=2). 
- __Migrate / Clone from URL__: [`https://github.com/iarsystems/bx-workspaces-ci`](https://github.com/iarsystems/bx-workspaces-ci).
- Edit the [Jenkinsfile](http://gitea:3000/jenkins/bx-workspaces-ci/_edit/master/Jenkinsfile)
   - update its Docker __agent__ settings to match your [bx-docker](https://github.com/iarsystems/bx-docker) image.


<img alt="Jenkins" align="right" src="https://avatars.githubusercontent.com/u/107424?s=72&v=4"/><br>

## Setting up Jenkins
It is finally __jenkins__ time. The standard Jenkins setup has a number of steps which can be automated with the [configuration-as-code][url-plugin-casc] plugin. 

The standard Jenkins setup has a number of steps that can be automated with the [configuration-as-code][url-plugin-casc] plugin. Given its fast-paced and complex ecosystem, plugin versions compatibility tend to break regarding interdependencies and the situation becomes worse for those living on the bleeding edge versions. For such reasons, it is reasonable to create a selection of plugin versions which were known to be in a working state for __reducing__ the chances of using broken plugin versions. For this, let's use a custom [Dockerfile](Dockerfile) that will:
* use the __jenkins/jenkins:lts-jdk11__ as base image, a stable version offering __LTS__ (Long-Term Support).
* use the __configuration-as-code__ plugin, so that we script the initial Jenkins [configuration](jcasc.yaml).
* use the `jenkins-plugin-cli` command line utility to install a collection of [plugins](plugins.txt) versions that are known to be working.

Build the image, tagging it as __jenkins:jcasc__:
```
docker build -t jenkins:jcasc ~/bx-jenkins-ci
```

Now run the __jenkins__ container:
> [!NOTE]
> Edit `JENKINS_ADMIN_ID` and `JENKINS_ADMIN_PASSWORD` for running with credentials other than `admin`/`password` for the Jenkins' administrative user.
```
docker run --name jenkins \
  --network jenkins --network-alias jenkins \
  --detach --restart unless-stopped \
  --env JENKINS_ADMIN_ID=admin \
  --env JENKINS_ADMIN_PASSWORD=password \
  --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client \
  --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  jenkins:jcasc
```

The plugin [__docker-workflow__][url-plugin-docker-workflow] requires a `docker` client available in the __jenkins__ container. Docker is unable to copy files directly from one container to another so an intermediate step through the host becomes necessary:
```
docker cp jenkins-docker:/usr/local/bin/docker ~
docker cp ~/docker jenkins:/usr/local/bin
rm ~/docker
docker exec jenkins docker --version
docker commit jenkins
```
The output should be similar to:
>```
>Successfully copied 34.8MB to /home/user
>Successfully copied 34.8MB to jenkins:/usr/local/bin
>Docker version 24.0.7, build afdd53b
>sha256:6dc192cfdd40b7006c6c152096070bd253c5b1f6b2ae5fc0e2fc683a15791825
>```

### Setting up the Docker Cloud plugin
It is time to configure the [__docker-cloud__][url-plugin-docker-cloud] plugin. In your web browser:

- Navigate to [http://jenkins:8080](http://jenkins:8080).
- Log in as "administrator" (e.g., __admin__).
- Go to __Configure a cloud →__.
- Select __New cloud__ → __Docker__.
- Name it `Jenkins cloud` and hit __`  Create  `__.
- Unfold __`  Docker Cloud details  `__.
- Fill __Docker Host URI__ with `tcp://docker:2376`
- Click on the ` Add ` drop-down list and select __Jenkins__.
- In "Kind" select __X.509 Client Certificate__.

When we started the __jenkins-docker__ container, server/client TLS certificates (and key) were automatically generated in the __jenkins-docker-certs__ volume. Those certificates are required to enable the __jenkins__ container to talk to the Docker deamon in the __jenkins-docker__ container. Open your Linux server's shell and issue the following commands:

| Item | Docker command |
| - | - |
| __Client Key__ | `docker exec jenkins-docker cat /certs/client/key.pem` |
| __Client Certificate__ | `docker exec jenkins-docker cat /certs/client/cert.pem` |
| __Server CA Certificate__ |  `docker exec jenkins-docker cat /certs/server/ca.pem` |

Go back to the Jenkins cloud creation page:
- Select the __Server credentials__ you just created, available from the drop-down list.
- Click __` Test Connection `__. You should get an output similar to: `Version = 24.0.7, API Version = 1.43`.
- Tick the __Enabled__ checkbox and, down below, click the ` Save ` button.

### Setting up the Gitea plugin
To configure the [__gitea__][url-plugin-gitea] plugin proceed as follows, starting from the Jenkins Dashboard (http://jenkins:8080):
- Go to __Manage Jenkins__.
- Go to __System__ under the "System Configuration" section (http://jenkins:8080/manage/configure).
- Scroll down to __Gitea Servers__ and click ` Add ` → __Gitea Server__.
- Name it (e.g.) "Gitea Server".
- Set __Server URL__ to `http://gitea:3000`. You should see `Gitea Version: 1.20.6` as response.
- Enable the __Manage hooks__ checkbox. This will allow Jenkins to manage the [webhooks][url-gitea-docs-webhooks] for the Gitea server.
   - ` Add ` a new __Jenkins__ (global) credential.
   - Change its "Kind" to __Gitea Personal Access Token__.
   - Paste the Gitea access token created during the Gitea server setup.
   - Give it a __Description__ (e.g. "Jenkins Token"), click __` Add `__ and then __` Save `__.

### Creating an Organization Folder
Go back to the Jenkins Dashboard (http://jenkins:8080):

- Click __New Item__.
- Select __Organization Folder__, give it a name (e.g. "Organization") and click __` OK `__.
- Select __Projects__ → "Repository Sources" → __` Add `__ → __Gitea Organization__.
- Select the "Jenkins Token" from the __Credentials__ drop-down list.
- Fill the __Owner__ field with the username you created for your Gitea server (e.g., `jenkins`) and __` Save `__.


## What happens next?
After that, Jenkins will use its multi-branch scan plugin to retrieve all the project repositories available on the Gitea Server.

When a project repository contains a [Jenkinsfile](https://github.com/IARSystems/bx-workspaces-ci/blob/master/Jenkinsfile) that uses a [declarative pipeline](https://www.jenkins.io/doc/book/pipeline/syntax/), Jenkins will then automatically execute the pipeline.

When the pipeline requests a Docker agent for the __docker-cloud__ plugin, it will automatically forward the request to the __jenkins-docker__ container so a new container based on the selected image is dynamically spawned during the workflow execution.
```groovy
pipeline {
  agent {
    docker {
      image 'iarsystems/bx<package>:<version>' 
      args '...'
  }
/* ... */
  stage('Build project') {
     steps {
       sh '/opt/iarsystems/bx<package>/common/bin/iarbuild project.ewp -build Release -log all'
      }
/* ... */
```

![jenkins-pipeline](https://github.com/felipe-iar/bx-jenkins-ci/assets/54443595/bf8af987-e9aa-48d9-8d21-8a24a1d6f0ba)

Jenkins will get a push notification from Gitea (via webhooks) whenever a monitored event is generated on the __owner__'s repositories.

Now you can start developing using the [IAR Embedded Workbench][url-iar-ew] and committing the project's code to the Gitea Server so you get automated builds and reports.

### Highlights
* The [__warnings-ng__][url-plugin-warnings-ng] plugin gives instantaneous feedback for every build on compiler-generated warnings as well violation warnings on conding standards provided by [IAR C-STAT](https://www.iar.com/cstat), our static code analysis tool for C/C++:

![jenkins-warnings-ng-cstat](https://github.com/felipe-iar/bx-jenkins-ci/assets/54443595/785ed739-be76-4650-b52e-87b31804d313)

* The [__gitea-checks__][url-plugin-gitea-checks] plugin has integrations with the [__warnings-ng__][url-plugin-warnings-ng] plugin. On the Gitea server, it can help you to spot failing checks on pull requests, preventing potentially defective code from being inadvertently merged into a project's production branch:

![gitea-warnings-ng](https://github.com/felipe-iar/bx-jenkins-ci/assets/54443595/04068ef2-edfd-40a7-80b4-4a2585f30e48)

> [!NOTE]
> Jenkins provides plugins for many other Git server providers such as GitHub, GitLab or Bitbucket. Although these services also offer their own CI infrastructure and runners. Gitea was picked for this tutorial for its simplicity to deploy in a container. Refer to [Managing Jenkins/Managing Plugins][url-jenkins-docs-plugins] for further details.


## Issues
Found an issue or have a suggestion specifically related to the [__bx-jenkins-ci__][url-repo] tutorial? Feel free to use the public issue tracker.
- Do not forget to take a look at [earlier issues][url-repo-issue-old].
- If creating a [new][url-repo-issue-new] issue, please describe it in detail.


## Summary
There you have it. A quickly deployable and reproducible setup where everything runs on containers. And that was just one of many ways of setting automated workflows using the IAR Build Tools. Using [Jenkins Configuration as Code][url-jenkins-jcasc] for setting up a new Jenkins controller simplifies the initial configuration by employing yaml syntax. Such configuration can be validated and reproduced in other Jenkins controllers.
   
Now you can learn from the scripts, from the [Dockerfile](Dockerfile) and from the official [Jenkins Documentation][url-jenkins-docs] which together sum up as a cornerstone for your organization to use them as they are or to customize them so that the containers run in suitable ways for particular needs.



<!-- Links -->
[url-iar-bx]:                 https://iar.com/bx
[url-iar-contact]:            https://iar.com/about/contact
[url-iar-cstat]:              https://iar.com/cstat
[url-iar-ew]:                 https://iar.com/products/overview
[url-iar-fs]:                 https://iar.com/products/requirements/functional-safety
[url-iar-mp]:                 https://iar.com/mypages
[url-iar-lms2]:               https://links.iar.com/lms2-server

[url-vi]:                     https://en.wikipedia.org/wiki/Vi
    
[url-bx-docker]:              https://github.com/iarsystems/bx-docker
[url-bx-workspaces-ci]:       https://github.com/iarsystems/bx-workspaces-ci

[url-docker-registry]:        https://docs.docker.com/registry
[url-docker-docs-net]:        https://docs.docker.com/network
 
[url-gitea]:                  https://gitea.io
[url-gitea-docs-webhooks]:    https://docs.gitea.io/en-us/webhooks
 
[url-jenkins]:                https://www.jenkins.io
[url-jenkins-jcasc]:          https://www.jenkins.io/projects/jcasc
[url-jenkins-docs]:           https://www.jenkins.io/doc
[url-jenkins-docs-plugins]:   https://www.jenkins.io/doc/book/managing/plugins

[url-plugin-casc]:            https://plugins.jenkins.io/configuration-as-code
[url-plugin-docker-cloud]:    https://plugins.jenkins.io/docker-plugin
[url-plugin-docker-workflow]: https://plugins.jenkins.io/docker-workflow
[url-plugin-gitea]:           https://plugins.jenkins.io/gitea
[url-plugin-gitea-checks]:    https://plugins.jenkins.io/gitea-checks
[url-plugin-warnings-ng]:     https://plugins.jenkins.io/warnings-ng
 
[url-repo]:                   https://github.com/iarsystems/bx-jenkins-ci
[url-repo-wiki]:              https://github.com/iarsystems/bx-jenkins-ci/wiki
[url-repo-issue-new]:         https://github.com/iarsystems/bx-jenkins-ci/issues/new
[url-repo-issue-old]:         https://github.com/iarsystems/bx-jenkins-ci/issues?q=is%3Aissue+is%3Aopen%7Cclosed
