#!/bin/bash

source novarc

export DEPLOY_VMLINUZ_UUID=$(openstack image show deploy-vmlinuz -f value -c id)
export DEPLOY_INITRD_UUID=$(openstack image show deploy-initrd -f value -c id)
export NETWORK_ID=$(openstack network show deployment -f value -c id)
export NODE_NAME01="ironic-node01"
export KVM_HOST_BRIDGE_IP=10.0.0.1
export VBMC_PORT=6230

openstack baremetal node create --name $NODE_NAME01 \
     --driver ipmi \
     --deploy-interface direct \
     --driver-info ipmi_address=$KVM_HOST_BRIDGE_IP \
     --driver-info ipmi_username=admin \
     --driver-info ipmi_password=password \
     --driver-info ipmi_port=$VBMC_PORT \
     --driver-info deploy_kernel=$DEPLOY_VMLINUZ_UUID \
     --driver-info deploy_ramdisk=$DEPLOY_INITRD_UUID \
     --driver-info cleaning_network=$NETWORK_ID \
     --driver-info provisioning_network=$NETWORK_ID \
     --property capabilities='boot_mode:uefi' \
     --resource-class baremetal-small \
     --property cpus=4 \
     --property memory_mb=4096 \
     --property local_gb=20
