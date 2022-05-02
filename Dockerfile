FROM jenkins/jenkins:lts-jdk11

ENV  JAVA_OPTS -Djenkins.install.runSetupWizard=false
ENV  CASC_JENKINS_CONFIG /var/jenkins_home/jcasc.yaml

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN  jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

COPY jcasc.yaml /var/jenkins_home/jcasc.yaml
