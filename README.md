# Overview

This project uses [Maas One][maasone] to install a virtual MAAS onto a single
physical host and then deploys OpenStack, including ironic, into that virtual
MAAS. A seperate virsh guest is also created which acts as the physical
machine which Ironic controls. Please see the [Charm Guide][charmguide] for more
details on deploying Ironic.

The instructions have been verified with a Bionic KVM host but should
work equally well with a later Ubuntu release.

> **Note**: Currently the instructions include a patch to apply to
  [Maas One][maasone]. This is obviously a very brittle approach so it is
  advised to use commit d71a76da of [Maas One][maasone] until this is fixed.


## Create SSH keys if needed.

If this is a freshly provisioned host generate an SSH key.

    [ -f /home/ubuntu/.ssh/id_rsa ] || { ssh-keygen -f /home/ubuntu/.ssh/id_rsa -q -N ""; }

## Prepare deployment directory

Create a temproary directory to store the branches used for the
deployment. Note that both this projet and [Maas One][maasone] are currently
a bit sloppy about storing disk images etc in the deployment directory.

    SCRIPT_DIR=$(mktemp -d --tmpdir=$HOME)
    chmod a+rx $SCRIPT_DIR
    cd $SCRIPT_DIR
    git clone https://github.com/pmatulis/maas-one
    git clone ironic-test-deploy

## Prepare deployment directory

The Ironic deploy requires an addional network for the MAAS and Neutron
gateway nodes so this hacky step patches it in

    cd $SCRIPT_DIR/maas-one
    patch -p1 < ../ironic-test-deploy/maas-one-ironic-patch.diff

## Install packages and snaps

Install packages and snaps needed by the setup scripts.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./install-tools.sh

Logout and back in again to apply changes to linux group membership.

## Create Ironic network

Create the Ironic network. This is the network Ironic managed
machines will deployed on to.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-ironic-net.sh

## Use [Maas One][maasone] to create virtual MAAS

Follow the instructions in the [Maas One][maasone] README.md

If the nodes do not appear in MAAS after they are first created, try
restarting them:

    $ virsh destroy node2
    Domain node2 destroyed

    $ virsh start node2
    Domain node2 started


Once the instructions have been completed there should now be a Juju model
backed by the new MAAS

## Create Juju Spaces

Create Juju spaces used by the bundle.

    juju add-space ironic 10.10.0.0/24
    juju add-space main 10.0.0.0/24

## Deploy OpenStack

Deploy OpenStack, including Ironic, onto the virtual MAAS

    cd $SCRIPT_DIR/ironic-test-deploy
    juju deploy ./ironic-bundle.yaml

## Deploy OpenStack

Set Temp-Url-Key in the service object storage account. This enables Ironic
to use the "direct" deploy method.

    juju run-action ironic-conductor/0 set-temp-url-secret --wait

## Create networks in openstack:

Create networks for the deployment.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-openstack-networks.sh

## Upload images:

Upload the two images needed duing iPXE (initramfs and kernel) and bare metal images.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./upload-images.sh

## Create flavors:

Create Ironic specific flavours

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-openstack-flavors.sh

## Create keypair:

Create a key pair.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-openstack-key.sh

## Create the 'physical' server that ironic will control:

Create a virsh guest outside of OpenStack which Ironic will control. This guest
will be mimicking a physical server.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-ironic-node.sh

## Setup virtual bmc:

To complete the illusion that this is a physical guest a virtual BMC server is
installed to control the guest.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./setup-vbmc.sh

Test vbmc:

    ipmitool -I lanplus -U admin -P password -H 10.0.0.1  -p 6230 power status

## Wipe iptables forwarding rules

The iptables forwarding rules setup by libvirt seem to mess with connectivity
between the baremetal server and Ironic so wipe them:

    sudo iptables -F FORWARD

## Create barmetal server:

Create a baremetal node that will map to the physical server.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-baremetal-node.sh

## Create barmetal server:

Create a port for the baremetal machine, the virtual port MAC address matches
that of the 'physical' server.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    ./create-baremetal-port.sh

## Prepare server:

Make 'physical' server available.

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    source novarc
    export NODE_NAME01="ironic-node01"
    export NODE_UUID01=$(openstack baremetal node show $NODE_NAME01  -f value -c uuid)
    openstack baremetal node manage $NODE_UUID01
    $ openstack baremetal node list
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
    | UUID                                 | Name          | Instance UUID | Power State | Provisioning State | Maintenance |
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
    | a2e7e048-b564-46e8-a695-c9298230b581 | ironic-node01 | None          | power on    | manageable         | False       |
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+

You can check on the progress by looking in the ironic-condictor log and using virsh console.
The common generic failure symptom is the node being stuck in 'clean wait' for more than ~5mins. If this happens
the `reset-clean-wait-node.sh` can be used to reset the server.

    openstack baremetal node provide $NODE_UUID01
    $ openstack baremetal node list
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
    | UUID                                 | Name          | Instance UUID | Power State | Provisioning State | Maintenance |
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+
    | a2e7e048-b564-46e8-a695-c9298230b581 | ironic-node01 | None          | power off   | available          | False       |
    +--------------------------------------+---------------+---------------+-------------+--------------------+-------------+

## Deploy Server:

Finally deploy the server:

    cd $SCRIPT_DIR/ironic-test-deploy/scripts
    source novarc
    export NETWORK_ID=$(openstack network show deployment -f value -c id)
    export IMAGE=$(openstack image show baremetal-focal  -f value -c id)
    openstack server create --flavor baremetal-small --key-name testkey --image $IMAGE --nic net-id=$NETWORK_ID test-server
    +-------------------------------------+--------------------------------------------------------+
    | Field                               | Value                                                  |
    +-------------------------------------+--------------------------------------------------------+
    | OS-DCF:diskConfig                   | MANUAL                                                 |
    | OS-EXT-AZ:availability_zone         |                                                        |
    | OS-EXT-SRV-ATTR:host                | None                                                   |
    | OS-EXT-SRV-ATTR:hypervisor_hostname | None                                                   |
    | OS-EXT-SRV-ATTR:instance_name       |                                                        |
    | OS-EXT-STS:power_state              | NOSTATE                                                |
    | OS-EXT-STS:task_state               | scheduling                                             |
    | OS-EXT-STS:vm_state                 | building                                               |
    | OS-SRV-USG:launched_at              | None                                                   |
    | OS-SRV-USG:terminated_at            | None                                                   |
    | accessIPv4                          |                                                        |
    | accessIPv6                          |                                                        |
    | addresses                           |                                                        |
    | adminPass                           | o49ZYbf8CKjW                                           |
    | config_drive                        |                                                        |
    | created                             | 2021-07-23T09:02:08Z                                   |
    | flavor                              | baremetal-small (26a98983-967b-4fe8-9e38-3ae356b46ac1) |
    | hostId                              |                                                        |
    | id                                  | 1740e089-84f7-4201-b503-13811bcbc95c                   |
    | image                               | baremetal-focal (815ddb5e-4e63-4533-a6b2-7e7651e27ae0) |
    | key_name                            | testkey                                                |
    | name                                | test-server                                            |
    | progress                            | 0                                                      |
    | project_id                          | ba98e9d1f5424557adfaf2bc46795be6                       |
    | properties                          |                                                        |
    | security_groups                     | name='default'                                         |
    | status                              | BUILD                                                  |
    | updated                             | 2021-07-23T09:02:08Z                                   |
    | user_id                             | 792dcb384df0414996c4b340e879419d                       |
    | volumes_attached                    |                                                        |
    +-------------------------------------+--------------------------------------------------------+

    openstack baremetal node list
    +--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
    | UUID                                 | Name          | Instance UUID                        | Power State | Provisioning State | Maintenance |
    +--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
    | a2e7e048-b564-46e8-a695-c9298230b581 | ironic-node01 | 1740e089-84f7-4201-b503-13811bcbc95c | power on    | active             | False       |
    +--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
    
    openstack server list
    +--------------------------------------+-------------+--------+------------------------+-----------------+-----------------+
    | ID                                   | Name        | Status | Networks               | Image           | Flavor          |
    +--------------------------------------+-------------+--------+------------------------+-----------------+-----------------+
    | 1740e089-84f7-4201-b503-13811bcbc95c | test-server | ACTIVE | deployment=10.10.0.187 | baremetal-focal | baremetal-small |
    +--------------------------------------+-------------+--------+------------------------+-----------------+-----------------+
    
    ssh 10.10.0.187 "uname -a"
    Linux test-server 5.4.0-48-generic #52-Ubuntu SMP Thu Sep 10 10:58:49 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux

<!-- LINKS -->

[maasone]: https://github.com/pmatulis/maas-one
[charmguide]: https://docs.openstack.org/project-deploy-guide/charm-deployment-guide/latest/ironic.html

