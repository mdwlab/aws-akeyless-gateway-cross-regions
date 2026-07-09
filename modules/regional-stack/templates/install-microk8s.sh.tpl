#!/bin/bash
# Rendered by Terraform and run once as EC2 user_data (cloud-init) on first
# boot. Terraform cannot manage in-cluster Kubernetes state directly, so this
# script only bootstraps MicroK8s itself; the Akeyless Gateway is installed
# into the cluster separately, by hand.
set -euxo pipefail

exec > /var/log/microk8s-install.log 2>&1

until [ -f /var/lib/cloud/instance/boot-finished ]; do
  sleep 2
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
