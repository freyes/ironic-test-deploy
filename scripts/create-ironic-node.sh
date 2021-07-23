#!/bin/sh -ex

OS_VARIANT=ubuntu18.04
POOL=images  # Remove 'pool' option below if not using a libvirt storage pool.

# The Juju controller

VCPUS=2
RAM_SIZE_MB=4000
DISK_SIZE_GB_1=30
NAME=baremetal1
MAC1="52:54:00:77:01:01"
MAC2="52:54:00:77:01:02"

virt-install \
  --os-variant $OS_VARIANT \
        --graphics vnc \
        --noautoconsole \
        --network network=ironic,mac=$MAC2 \
        --name $NAME \
        --vcpus $VCPUS \
        --cpu host \
        --memory $RAM_SIZE_MB \
        --disk "$NAME"_1.img,size=$DISK_SIZE_GB_1,serial=workaround-lp-1876258-"$NAME"_1 \
        --boot network

# The usable MAAS nodes
