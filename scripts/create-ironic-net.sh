#!/bin/sh -e

virsh net-define net-ironic.xml                                               
virsh net-start ironic                                                        
virsh net-autostart ironic

