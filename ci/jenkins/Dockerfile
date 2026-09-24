# Jenkins controller with every CLI tool the OnTrack pipeline needs baked in.
# Tools run inside Jenkins (not in throwaway containers) so they can read the
# workspace directly - no host bind-mount path problems.
FROM jenkins/jenkins:lts-jdk17

USER root

# Base tools + Node (for Newman)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip jq nodejs npm \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

# Newman (Postman CLI) for API smoke / CRUD tests
RUN npm install -g newman@6 && npm cache clean --force

# Trivy (image + IaC scanning)
# Pinned to v0.69.3, listed as SAFE in advisory GHSA-69fq-xp46-6x23 (CVE-2026-33634,
# March 2026 Trivy supply-chain compromise: v0.69.4 was malicious and older releases
# were removed). The tarball is verified against the official checksum file.
ARG TRIVY_VERSION=0.69.3
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/64bit/; s/arm64/ARM64/') \
 && BASE=https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION} \
 && FILE=trivy_${TRIVY_VERSION}_Linux-${ARCH}.tar.gz \
 && curl -sSfL -o /tmp/${FILE} ${BASE}/${FILE} \
 && curl -sSfL -o /tmp/trivy_checksums.txt ${BASE}/trivy_${TRIVY_VERSION}_checksums.txt \
 && cd /tmp && grep " ${FILE}$" trivy_checksums.txt | sha256sum -c - \
 && tar -xzf /tmp/${FILE} -C /usr/local/bin trivy \
 && rm -f /tmp/${FILE} /tmp/trivy_checksums.txt \
 && trivy --version

# Gitleaks (secret scanning)
ARG GITLEAKS_VERSION=8.21.2
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/x64/') \
 && curl -sSL https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz \
      | tar -xz -C /usr/local/bin gitleaks

# SonarScanner CLI (bundles its own JRE)
ARG SONAR_SCANNER_VERSION=6.2.1.4610
RUN ARCH=$(dpkg --print-architecture | sed 's/amd64/x64/; s/arm64/aarch64/') \
 && curl -sSLo /tmp/ss.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-${ARCH}.zip \
 && unzip -q /tmp/ss.zip -d /opt \
 && ln -s /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-${ARCH}/bin/sonar-scanner /usr/local/bin/sonar-scanner \
 && rm /tmp/ss.zip

# Plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# NOTE: the container runs as root (see docker-compose.yml) so it can use the
# host Docker socket on Windows, macOS and Linux alike. Acceptable for a local
# lab; in real production you would use a dedicated agent + docker group.
