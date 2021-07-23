#!/bin/bash

source novarc

export RAM_MB=2048
export CPU=2
export DISK_GB=6
export FLAVOR_NAME="baremetal-small"

openstack flavor create --ram $RAM_MB --vcpus $CPU --disk $DISK_GB $FLAVOR_NAME
openstack flavor set --property resources:CUSTOM_BAREMETAL_SMALL=1 $FLAVOR_NAME

openstack flavor set --property resources:VCPU=0 $FLAVOR_NAME
openstack flavor set --property resources:MEMORY_MB=0 $FLAVOR_NAME
openstack flavor set --property resources:DISK_GB=0 $FLAVOR_NAME

