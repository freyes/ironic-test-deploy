#!/bin/bash

export NODE_UUID01=$(openstack baremetal node show $NODE_NAME01 --format json | jq -r .uuid)
ironic node-set-maintenance $NODE_NAME01 on
ironic --ironic-api-version 1.16 node-set-provision-state $NODE_NAME01 abort
ironic node-set-maintenance $NODE_NAME01 off
ironic node-set-provision-state $NODE_NAME01 manage
