#!/bin/bash

source novarc

openstack router create ironic-router
openstack network create Pub_Net --external --share --default    --provider-network-type flat --provider-physical-network physnet1
openstack subnet create Pub_Subnet --allocation-pool start=10.0.0.200,end=10.0.0.250 --subnet-range 10.0.0.0/24 --no-dhcp --gateway 10.0.0.1 --network Pub_Net
openstack router set --external-gateway Pub_Net ironic-router
openstack network create \
     --share \
     --provider-network-type flat \
     --provider-physical-network physnet2 \
     deployment

# Set gateway to be router IP
openstack subnet create \
     --network deployment \
     --dhcp \
     --subnet-range 10.10.0.0/24 \
     --gateway 10.10.0.1 \
     --ip-version 4 \
     --allocation-pool start=10.10.0.100,end=10.10.0.254 \
     deployment

openstack router add subnet ironic-router deployment
