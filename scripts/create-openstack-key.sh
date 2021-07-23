#!/bin/bash

source novarc

openstack keypair create --public-key /home/ubuntu/.ssh/id_rsa.pub testkey
