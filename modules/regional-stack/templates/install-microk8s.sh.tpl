#!/bin/bash
# Rendered by Terraform and run once as EC2 user_data (cloud-init) on first
# boot. Terraform cannot manage in-cluster Kubernetes state directly, so this
# script only bootstraps MicroK8s itself; the Akeyless Gateway is installed
# into the cluster separately, by hand.
set -euxo pipefail

exec > /var/log/microk8s-install.log 2>&1

# Bounded wait for any concurrent apt/dpkg lock (e.g. unattended-upgrades
# running at first boot) rather than cloud-init's own completion marker:
# this script runs as part of cloud-init's final stage (scripts-user, which
# executes before the final-message module that writes boot-finished), so
# waiting on cloud-init to finish here would deadlock against itself.
for i in $(seq 1 60); do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

apt-get update -y
apt-get install -y snapd

snap install microk8s --classic --channel="${microk8s_channel}"

usermod -a -G microk8s ubuntu
mkdir -p /home/ubuntu/.kube
chown -R ubuntu:ubuntu /home/ubuntu/.kube

/snap/bin/microk8s status --wait-ready --timeout 300
/snap/bin/microk8s enable ${microk8s_addons}

echo "alias kubectl='microk8s kubectl'" >> /home/ubuntu/.bashrc

touch /var/log/microk8s-install-complete
