# cluster-node-init - v0.1

As part of the work I am doing to setup my 12 nodes Raspberry PI 4 cluster, I built a simple cloud-init replacement in bash.

Tens, if not hundreds, of different solutions exist to perform a Virtual Machine initialization but they are, usually, full of features that are very often useless when it comes to a bare-metal cluster, even more true if it's a Raspberry PI 4 cluster.
The resource constraint, the slowness and the extreme **instability** of cloud-init have pushed me to build this really simple deployment pipeline in bash.

My cluster boots entirely via PXE and TFTP and the rootfs is an overlayfs virtual filesystem exported via NFS, because I have built this platform with that in mind the configuration is a file available on the disk of the node. Currently it's not possible to fetch the configuration from an external system but will be added soon.
Also, the goal of this platform is to let me to destroy any node any time, simply deleting the rootfs folder on the storage of the master node, and rebuild it automatically with zero effort therefore some operations (like system updates, package installation, etc.) are performed on every boot although the platform aims to be idempotent therefore is a safe operation.

With this approach, and thanks to this cloud-init simplified replacement, a single node can be bootstrapped with already the updates installed in the base image and it takes <90s for the first boot and 40-ish seconds afterwards.

Only Ubuntu 20.10 64bit has been tested so far but should work safely on Ubuntu 20.04 and also on Raspbian, both 32bit and 64bit.

A number of modules are already available
- remove-cloud-init
- hostname-configure
- disks-configure
- keep-vt-logs-console
- network-configure
- apt-configure
- apt-update
- apt-upgrade
- apt-install-packages
- apparmor-disable
- sshd-configure
- users-configure
- print-info

A few modules still need to be implemented
- apt-configure
- network-configure
- snap-install-packages
- timezone-configure
- ntp-configure 

Because the network-configure module is a WIP, the deploy mechanism relies on a network configurable via DHCP on eth0, as per default on the raspberry pi. The wifi auto configuration hasn't been tested and most likely it will not work.

Please take a look at [config.env.skel](config.env.skel) for the configuration parameters, keep in mind that this file is sourced by the main bash script and therefore can contain actual commands.
On a longer term the goal is to support something more convenient like YAML.

## Installation

Although this the platform has been built with a rootfs over nfs, it can be easily installed directly on the disk:
```
cd /opt
sudo git clone https://github.com/danielealbano/cluster-node-init.git
sudo cp /opt/cluster-node-init/config.env.skel /opt/cluster-node-init/config.env
sudo nano /opt/cluster-node-init/config.env # update the config as needed
sudo mkdir /etc/systemd/system/multi-user.target.wants
sudo ln -s /opt/cluster-node-init/cluster-node-init.service /etc/systemd/system/multi-user.target.wants/cluster-node-init.service
sudo systemctl daemon-reload
```

These instructions can easily be adapted to deploy cluster-node-init over rootfs exported via fs, just use relative paths, ie.
```
cd path/to/rootfs/over/nfs
cd opt
sudo git clone https://github.com/danielealbano/cluster-node-init.git
sudo cp opt/cluster-node-init/config.env.skel opt/cluster-node-init/config.env
sudo nano opt/cluster-node-init/config.env # update the config as needed
sudo mkdir ../etc/systemd/system/multi-user.target.wants
cd ../etc/systemd/system/multi-user.target.wants
sudo ln -s ../../opt/cluster-node-init/cluster-node-init.service cluster-node-init.service
```

## Modules documentation

The platform takes care of verifying that all the modules requested in the config file actually exist and are executable before starting and retries any failure during the deployment process to handle transient errors.

### remove-cloud-init

Takes care of removing cloud-init, first thing to do ;)

There are no config parameters available for this module.

### hostname-configure

Configures the hostname and optionally re-run dhclient to send to the dhcp server the updated hostname.

Available parameters:

| Parameter | Details |
| - | - |
| HOSTNAME | Set the hostname of the machine to the value specified in the variable |
| HOSTNAME_CMD | Execute the command defined in the variable and use the output as hostname, if this parameter is set takes precedence |
| HOSTNAME_DOMAIN  | If set, set the domain name to the specified value |
| HOSTNAME_DHCLIENT_RERUN  | TODO |
| HOSTNAME_DHCLIENT_DEV  | TODO |

### disks-configure

Takes care of configuring the attached disks as per configuration if there is no partition table created, otherwise skips all the write operations and only updates the /etc/fstab.
The expectation is that the attached disks are configured via this module, if not it's necessary to:
- update the configuration to match the partitions type and size on the disks;
- ensure that all the swaps / filesystems have been created;
- ensure that all the swaps / filesystems have an UUID.

Available parameters:

| Parameter | Details |
| - | - |
| DISKS_{X}\_DEV | Disk device |
| DISKS_{X}\_PARTITION_{Y}\_FS | Filesystem (ie. swap, ext4, etc.), must be a filesystem support by default in the system without additional software |
| DISKS_{X}\_PARTITION_{Y}\_SIZE | Size (ie. 4G), it's possible to pass "all" for the last partition to use all the remaining available space |
| DISKS_{X}\_PARTITION_{Y}\_MOUNT_POINT | Path of the mount point |
| DISKS_{X}\_PARTITION_{Y}\_MKFS_EXTRA_PARAM | Extra parameters to pass to mkfs or mkswap, by default -U is already passed and can't be specified again |

### keep-vt-logs-console

Avoids clearing the tty1 after the boot is completed, handy to see any error if a screen is attached or to read the system info printed by the **print-info** module.

There are no config parameters available for this module.

### apt-update

Runs apt update, relies on the pkgcache.bin modification timestamp to avoid re-running the update on every boot.

Available parameters:

| Parameter | Details |
| - | - |
| APT_UPDATE_PKGCACHE_BIN_LAST_REFRESH_DIFF_IN_S | Seconds to wait between apt update runs |

### apt-upgrade

Runs a system update, ensure that the software install in the system is up-to-date before finishing the boot.

The kernel related packages are **specifically** excluded as my cluster is running off PXE and TFTP and the kernel is provided via the master node.

There are no config parameters available for this module.

### apt-install-packages

Installs the specified packages via apt install. Because it runs on every boot, it's possible to add additional software and get it installed at boot time.

Available parameters:

| Parameter | Details |
| - | - |
| APT_INSTALL_PACKAGES | List of packages to install space-separated |

### apparmor-disable

Disables apparmor if requested.

| Parameter | Details |
| - | - |
| APPARMOR_DISABLE | Seconds to wait between apt update runs |

### sshd-configure

Ensures that the ssh host keys exist.

There are no config parameters available for this module.

### users-configure

Creates or updates the user(s) defined in the configuration. As currently it's not possible to define the home directory path in, if an user already exists and the option USER_{X}\_CREATE_HOME is set to 1 after its creation, it will be ignored.

This module also takes care of adding any requested ssh auth key and setting the NOPASSWD flag for the user in /etc/sudoers if requested.

Available parameters:

| Parameter | Details |
| - | - |
| USER_{X}_NAME                     | User name of the user to create |
| USER_{X}_CREATE_HOME              | If set to 1, creates the home directory |
| USER_{X}_SUDO_NOPASSWD            | If set to 1, set the NOPASSWD flag in sudo for the user |
| USER_{X}_GROUP                    | If not specified the default will be used |
| USER_{X}_GROUPS                   | Additional user groups (comma separated, no whitespaces!) |
| USER_{X}_ADD_CREATE_OPTS_OVERRIDE | Override ALL the create options (to specificy different home, comments, etc.) |
| USER_{X}_SSH_AUTH_KEYS_{Y}        | Pre-authorised ssh keys |

### print-info

Prints out the node ip address(es), hostname and ssh host keys for reference.
