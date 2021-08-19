#!/bin/bash -eux

# dependencies:
# sudo apt install jq
# sudo snap install --classic juju-wait

export SNAP_CLOUDS_YAML="/var/snap/freyes-ovb/common/clouds.yaml"

# Create the Ironic network. This is the network Ironic managed machines will
# deployed on to.
source ~/novarc  # undercloud creds
openstack network show ironic_net || openstack network create --disable-port-security ironic_net
sleep 5
neutron subnet-show ironic_subnet || neutron subnet-create --disable-dhcp --name ironic_subnet --dns-nameserver 8.8.8.8 ironic_net 10.10.0.0/24
sleep 5
neutron router-interface-add freyes_router ironic_subnet || echo "ironic_subnet already in the router?"
sleep 5
# create a server to be used as baremetal
openstack server show baremetal-node00 || openstack server create --wait --network ironic_net --image ipxe-boot --flavor m1.blue baremetal-node00

export BAREMETAL_NODE00_ID=$(openstack server show -f value -c id baremetal-node00)

set +e
DATA_PORT="$(juju config neutron-gateway data-port)"
if [ "$?" != 0 ] || [ -z "$DATA_PORT" ]; then
  juju deploy ./ironic-bundle.yaml
fi
set -e
juju show-application openstackbmc-controller || juju deploy cs:ubuntu openstackbmc-controller
juju wait

juju config neutron-gateway data-port | grep br-ex || ./add-data-ports.sh neutron-gateway freyes_admin_net br-ex
juju wait
juju config neutron-gateway data-port | grep br-deployment || ./add-data-ports.sh neutron-gateway ironic_net br-deployment
juju wait

juju ssh openstackbmc-controller/0 "sudo snap install --edge freyes-ovb"

cat << EOF > /tmp/clouds.yaml
clouds:
  serverstack:
    region_name: $OS_REGION_NAME
    auth:
      auth_url: $OS_AUTH_URL
      username: $OS_USERNAME
      password: $OS_PASSWORD
      project_name: $OS_PROJECT_NAME
      project_domain_name: $OS_PROJECT_DOMAIN_NAME
      user_domain_name: $OS_USER_DOMAIN_NAME
EOF
juju scp /tmp/clouds.yaml openstackbmc-controller/0:/tmp/clouds.yaml
juju ssh openstackbmc-controller/0 "sudo cp /tmp/clouds.yaml $SNAP_CLOUDS_YAML"

# add a port in the deployment network to ironic-conductor units
i=0
for JUJU_MACHINE_ID in $(juju status --format json | jq -r '.applications."ironic-conductor".units|.[]|.machine' | xargs echo); do
  INSTANCE_ID=$(juju show-machine --format json $JUJU_MACHINE_ID | jq -r '.machines|.[]|."instance-id"')
  if openstack port show "ironic-conductor-port$i"; then
    PORT_ID=$(openstack port show -f value -c id "ironic-conductor-port$i")
  else
    PORT_ID=$(openstack port create --network ironic_net -f value -c id "ironic-conductor-port$i")
  fi
  if [ "$(openstack port show -c device_id -f value $PORT_ID)" != "$INSTANCE_ID" ]; then
    openstack server add port $INSTANCE_ID $PORT_ID
  fi

  # the deployment network has no dhcp, so we need to drop a netplan
  # configuration inside the machine
  MAC_ADDRESS=$(openstack port show -f value -c mac_address $PORT_ID)
  IP_ADDRESS=$(openstack port show -f json -c fixed_ips $PORT_ID | jq -r '.fixed_ips|.[]|.ip_address')
  cat << EOF > /tmp/deployment-port.yaml
network:
    ethernets:
        eth-ironic:
            dhcp4: false
            addresses:
                - $IP_ADDRESS/24
            gateway4: 10.10.0.1
            match:
                macaddress: $MAC_ADDRESS
            set-name: eth-ironic
    version: 2
EOF
  juju scp /tmp/deployment-port.yaml $JUJU_MACHINE_ID:/tmp
  juju ssh $JUJU_MACHINE_ID "sudo cp /tmp/deployment-port.yaml /etc/netplan/99-deployment-port.yaml"
  juju ssh $JUJU_MACHINE_ID "sudo netplan apply"
  i=$((i+1))
done

juju run-action ironic-conductor/0 set-temp-url-secret --wait

source scripts/novarc  # overcloud

# source: create-openstack-networks.sh
openstack router create ironic-router
openstack network create Pub_Net \
          --external --share --default \
          --provider-network-type flat \
          --provider-physical-network physnet1

openstack subnet create Pub_Subnet \
          --allocation-pool start=10.5.0.200,end=10.5.0.250 \
          --subnet-range 10.5.0.0/24 \
          --no-dhcp \
          --gateway 10.5.0.1 \
          --network Pub_Net

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


# upload images to the overcloud
if [[ ! -f ironic-python-agent.initramfs ]]; then
    wget http://10.245.161.162/swift/v1/images/ironic-python-agent.initramfs
fi
if [[ ! -f ironic-python-agent.kernel ]]; then
    wget http://10.245.161.162/swift/v1/images/ironic-python-agent.kernel
fi
if [[ ! -f baremetal-ubuntu-focal.img ]]; then
    wget http://10.245.161.162/swift/v1/images/baremetal-ubuntu-focal.img
fi

for release in focal
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

# source: create-openstack-flavors.sh
export RAM_MB=2048
export CPU=2
export DISK_GB=6
export FLAVOR_NAME="baremetal-small"

openstack flavor create --ram $RAM_MB --vcpus $CPU --disk $DISK_GB $FLAVOR_NAME
openstack flavor set --property resources:CUSTOM_BAREMETAL_SMALL=1 $FLAVOR_NAME
openstack flavor set --property resources:VCPU=0 $FLAVOR_NAME
openstack flavor set --property resources:MEMORY_MB=0 $FLAVOR_NAME
openstack flavor set --property resources:DISK_GB=0 $FLAVOR_NAME

test -f testkey.pub || ssh-keygen -t rsa -N "" -C "test key" -f testkey
openstack keypair create --public-key testkey.pub testkey

############
# TODO: here we need to setup the BMC
export NODE_NAME01="baremetal-node00"
export IPMI_ADDRESS=$(juju run --unit openstackbmc-controller/0 'unit-get public-address')
export IPMI_PORT=6230

cat << EOF > /tmp/openstackbmc.service
[Unit]
Description=openstack-bmc baremetal-node00 Service

[Service]
Environment="OS_CLIENT_CONFIG_FILE=$SNAP_CLOUDS_YAML"
ExecStart=/snap/bin/freyes-ovb.openstackbmc --instance $BAREMETAL_NODE00_ID --address $IPMI_ADDRESS
Restart=always

User=root
StandardOutput=kmsg+console
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOF
juju scp /tmp/openstackbmc.service openstackbmc-controller/0:/tmp/
juju ssh openstackbmc-controller/0 "sudo cp /tmp/openstackbmc.service /usr/lib/systemd/system/openstackbmc-$IPMI_PORT.service"
juju ssh openstackbmc-controller/0 "sudo systemctl daemon-reload"
juju ssh openstackbmc-controller/0 "sudo systemctl restart openstackbmc-$IPMI_PORT.service"

############


# Create a baremetal node that will map to the physical server.

export DEPLOY_VMLINUZ_UUID=$(openstack image show deploy-vmlinuz -f value -c id)
export DEPLOY_INITRD_UUID=$(openstack image show deploy-initrd -f value -c id)
export FOCAL_IMAGE_UUID=$(openstack image show -f value -c id baremetal-focal)
export NETWORK_ID=$(openstack network show deployment -f value -c id)

openstack baremetal node create --name $NODE_NAME01 \
     --driver ipmi \
     --deploy-interface direct \
     --driver-info ipmi_address=$IPMI_ADDRESS \
     --driver-info ipmi_username=admin \
     --driver-info ipmi_password=password \
     --driver-info ipmi_port=$IPMI_PORT \
     --driver-info deploy_kernel=$DEPLOY_VMLINUZ_UUID \
     --driver-info deploy_ramdisk=$DEPLOY_INITRD_UUID \
     --driver-info cleaning_network=$NETWORK_ID \
     --driver-info provisioning_network=$NETWORK_ID \
     --property capabilities='boot_mode:uefi' \
     --resource-class baremetal-small \
     --property cpus=2 \
     --property memory_mb=2048 \
     --property local_gb=15
# ^ m1.blue flavor used for VM on the undercloud that will act as baremetal.
openstack baremetal node set $NODE_NAME01 \
    --instance-info image_source=$FOCAL_IMAGE_UUID


export NODE_NAME00="baremetal-node00"
export NODE_UUID00=$(openstack baremetal node show -f value -c uuid $NODE_NAME00)
source ~/novarc  # we need to query the undercloud
export MAC=$(openstack port list --server baremetal-node00 -f value -c "MAC Address")

source scripts/novarc
openstack baremetal port create $MAC \
     --node $NODE_UUID00 \
     --physical-network=physnet2

openstack baremetal node manage $NODE_UUID00
openstack baremetal node list
