#!/bin/bash

source novarc

export NODE_NAME01="ironic-node01"
export NODE_UUID01=$(openstack baremetal node show $NODE_NAME01 --format json | jq -r .uuid)
export MAC="52:54:00:77:01:02"

openstack baremetal port create $MAC \
     --node $NODE_UUID01 \
     --physical-network=physnet2
