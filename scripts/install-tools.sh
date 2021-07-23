#!/bin/sh -e

cd
sudo apt update
sudo apt install -y jq python3-pip libvirt-dev virtualenv virtinst qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils ipmitool
sudo snap install openstackclients
sudo adduser `id -un` libvirt
sudo adduser `id -un` kvm


