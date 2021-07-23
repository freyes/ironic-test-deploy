#!/bin/bash

source novarc

if [[ ! -f ironic-python-agent.initramfs ]]; then
    wget http://10.245.161.162/swift/v1/images/ironic-python-agent.initramfs
fi
if [[ ! -f ironic-python-agent.kernel ]]; then
    wget http://10.245.161.162/swift/v1/images/ironic-python-agent.kernel
fi
if [[ ! -f baremetal-ubuntu-focal.img ]]; then
    wget http://10.245.161.162/swift/v1/images/baremetal-ubuntu-focal.img
fi

for release in bionic focal
do
    glance image-create \
        --store swift \
        --name baremetal-$release \
        --disk-format raw \
        --container-format bare \
        --file baremetal-ubuntu-$release.img --progress
done

glance image-create \
    --store swift \
    --name deploy-vmlinuz \
    --disk-format aki \
    --container-format aki \
    --visibility public \
    --file ironic-python-agent.kernel --progress

glance image-create \
    --store swift \
    --name deploy-initrd \
    --disk-format ari \
    --container-format ari \
    --visibility public \
    --file ironic-python-agent.initramfs --progress
