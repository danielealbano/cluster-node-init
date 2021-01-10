# cluster-node-init - v0.1

As part of the work I am doing to setup my 12 nodes Raspberry PI 4 cluster, I built a simple cloud-init replacement in bash.

Tens, if not hundreds, of different solutions exist to perform a Virtual Machine initialization but they are, usually, full of features that are very often useless when it comes to a bare-metal cluster, even more true if it's a Raspberry PI 4 cluster.
The resource constraint, the slowness and the extreme **instability** of cloud-init have pushed me to build this really simple deployment pipeline in bash.

My cluster boots entirely via PXE and TFTP and the rootfs is an overlayfs virtual filesystem exported via NFS, because I have built this platform with that in mind the configuration is a file available on the disk of the node. Currently it's not possible to fetch the configuration from an external system but will be added soon.
Also, the goal of this platform is to let me to destroy any node any time, simply deleting the rootfs folder on the storage of the master node, and rebuild it automatically with zero effort therefore some operations (like system updates, package installation, etc.) are performed on every boot although the platform aims to be idempotent therefore is a safe operation.

With this approach, and thanks to this cloud-init simplified replacement, a single node can be fully bootstrapped with already the updates installed in the base image and it takes <90s for the first boot and 40-ish seconds afterwards.

Only Ubuntu 20.10 64bit has been tested so far but should work safely on Ubuntu 20.04 and also on Raspbian, both 32bit and 64bit.

This approach comes handy also for embedded / IoT devices, it makes possible to have a cloud-init configuration approach with a minimal enviroment available (ie. a buildroot / yocto based system where you want to retain the flexibility to run a set of steps at boot to perform the auto-configuration).

A number of modules are already available
- [remove-cloud-init](#remove-cloud-init)
- [hostname-configure](#hostname-configure)
- [disks-configure](#disks-configure)
- [keep-vt-logs-console](#keep-vt-logs-console)
- [network-configure](#network-configure)
- [apt-configure](#apt-configure)
- [apt-update](#apt-update)
- [apt-upgrade](#apt-upgrade)
- [apt-install-packages](#apt-install-packages)
- [apparmor-disable](#apparmor-disable)
- [sshd-configure](#sshd-configure)
- [users-configure](#users-configure)
- [print-info](#print-info)

A few modules still need to be implemented
- apt-configure
- network-configure
- snap-install-packages
- timezone-configure
- ntp-configure
- run-custom

Because the network-configure module is a WIP, the deploy mechanism relies on a network configurable via DHCP on eth0, as per default on the raspberry pi. The wifi auto configuration hasn't been tested and most likely it will not work.

An [example configuration](#example-configuration) is available in the documentation and also in the repository, keep in mind that this file is sourced by the main bash script and therefore can contain actual commands. On a longer term the goal is to support something more convenient like YAML.

## Installation

### Current machine

Although this the platform has been built with a rootfs over nfs, it can be easily installed directly on a machine:
```
cd /opt
sudo git clone https://github.com/danielealbano/cluster-node-init.git
sudo cp /opt/cluster-node-init/config.env.skel /opt/cluster-node-init/config.env
sudo nano /opt/cluster-node-init/config.env # update the config as needed
sudo mkdir /etc/systemd/system/multi-user.target.wants
sudo ln -s /opt/cluster-node-init/cluster-node-init.service /etc/systemd/system/multi-user.target.wants/cluster-node-init.service
sudo systemctl daemon-reload
```

### rootfs via a sdcard

If you have flashed an sdcard you can mount the rootfs and run the following commands
```
cd path/to/sdcard/rootfs
cd opt
sudo git clone https://github.com/danielealbano/cluster-node-init.git
sudo cp cluster-node-init/config.env.skel cluster-node-init/config.env
sudo nano cluster-node-init/config.env # update the config as needed
sudo mkdir ../etc/systemd/system/multi-user.target.wants
cd ../etc/systemd/system/multi-user.target.wants
sudo ln -s ../../opt/cluster-node-init/cluster-node-init.service cluster-node-init.service
```

### rootfs exported over NFS

The instructions are really similar to the ones used for the sdcard
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

Legend:
- {X} is an index starting from 0 and indicates the disk index in the configuration
- {Y} is an index starting from 0 and indicates the partition index for the related disk in the configuration

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

Legend:
- {X} is an index starting from 0 and indicates the user index in the configuration
- {Y} is an index starting from 0 and indicates the ssh auth key index for the related user in the configuration

### print-info

Prints out the node ip address(es), hostname and ssh host keys for reference.

## Example configuration

A skeleton config file named [config.env.skel](config.env.skel) is available in the repository.

```
# Should really be converted in YAML or JSON :)

# general settings
# ---
# MODULE_LIST                       List of modules to execute in order
# MODULE_EXECUTION_MAX_RETRIES      Max number of retries in case of a module failure
# MODULE_EXECUTION_RETRY_WAIT       How much time to wait after a module failure
#
MODULE_LIST=""
MODULE_LIST="${MODULE_LIST} remove-cloud-init hostname-configure disks-configure timezone-configure keep-vt-logs-console"
MODULE_LIST="${MODULE_LIST} network-configure apt-configure apt-update apt-upgrade apt-install-packages"
MODULE_LIST="${MODULE_LIST} snap-install-packages ntp-configure apparmor-disable sshd-configure users-configure"
MODULE_LIST="${MODULE_LIST} print-info"
MODULE_EXECUTION_MAX_RETRIES=3
MODULE_EXECUTION_MAX_RETRY_WAIT_IN_SECONDS=5


# hostname-configure
# ---
# HOSTNAME                          Set the hostname of the machine to the value specified in the variable
# HOSTNAME_CMD                      Execute the command defined in the variable and use the output as hostname, if
#                                   this parameter is set takes precedence
# HOSTNAME_DOMAIN                   If set, set the domain name to the specified value
# HOSTNAME_DHCLIENT_RERUN
# HOSTNAME_DHCLIENT_DEV
#
HOSTNAME=""
HOSTNAME_CMD="echo 'rpi4-$(cat /proc/cpuinfo | grep Serial | awk "{ printf \$3 }" | cut -b 9-)'"
HOSTNAME_DOMAIN="worker.k8s-cluster.home"
HOSTNAME_DHCLIENT_RERUN=1
HOSTNAME_DHCLIENT_DEV="eth0"


# disks-configure
# ---
# Simple disk configuration, currently supports only msdos partitions (no gpt) and doesn't support raid or lvm.
# If a partition table is present on the disk, the configuration will be ALWAYS skipped, we don't want to lose data.
#
DISKS_0_DEV="/dev/sda"
DISKS_0_PARTITION_0_FS="swap"
DISKS_0_PARTITION_0_SIZE="4G"
DISKS_0_PARTITION_0_MOUNT_POINT="swap"
DISKS_0_PARTITION_0_MKFS_EXTRA_PARAM="-L NVME_SWAP"
DISKS_0_PARTITION_1_FS="ext4"
DISKS_0_PARTITION_1_SIZE="all"
DISKS_0_PARTITION_1_MOUNT_POINT="/mnt/data"
DISKS_0_PARTITION_1_MKFS_EXTRA_PARAM="-L NVME_DATA"


# apt-update-system
# ---
# APT_UPDATE_PKGCACHE_BIN_LAST_REFRESH_DIFF_IN_S
#
APT_UPDATE_PKGCACHE_BIN_LAST_REFRESH_DIFF_IN_S=86400


# apt-install-packages
# ---
# APT_INSTALL_PACKAGES
#
APT_INSTALL_PACKAGES=""
APT_INSTALL_PACKAGES="${APT_INSTALL_PACKAGES} mc nano redis-tools iperf3 iftop htop rng-tools python3-pip python3-pil"
APT_INSTALL_PACKAGES="${APT_INSTALL_PACKAGES} python3-smbus python3-rpi.gpio python3-psutil i2c-tools fonts-freefont-ttf"
APT_INSTALL_PACKAGES="${APT_INSTALL_PACKAGES} ifenslave build-essential cmake flex bison gdb autoconf automake gcc-9"
APT_INSTALL_PACKAGES="${APT_INSTALL_PACKAGES} g++-9 gdb gdbserver lcov ca-certificates libraspberrypi-bin"


# apparmor-disable
# ---
# APPARMOR_DISABLE                  Set to 1 to disable apparmor
#
APPARMOR_DISABLE=1


# sshd-configure
# ---
# NO CONFIG PARAMETER SUPPORTED
#


# users-configure
# ---
# Supported params ({X} and {Y} are indexes from 0 onwards, must be sequential)
# USER_{X}_NAME                     User name of the user to create
# USER_{X}_CREATE_HOME              If set to 1, creates the home directory
# USER_{X}_SUDO_NOPASSWD            If set to 1, set the NOPASSWD flag in sudo for the user
# USER_{X}_GROUP                    If not specified the default will be used
# USER_{X}_GROUPS                   Additional user groups (comma separated, no whitespaces!)
# USER_{X}_ADD_CREATE_OPTS_OVERRIDE Override ALL the create options (to specificy different home, comments, etc.)
# USER_{X}_SSH_AUTH_KEYS_{Y}        Pre-authorised ssh keys
#
USER_0_NAME="ubuntu"
USER_0_CREATE_HOME=1
USER_0_SUDO_NOPASSWD=1
USER_0_SHELL="/bin/bash"
USER_0_GROUP=""
USER_0_GROUPS="adm,audio,cdrom,dialout,dip,floppy,lxd,netdev,plugdev,sudo,video"
USER_0_ADD_CREATE_OPTS_OVERRIDE=""
USER_0_SSH_AUTH_KEYS_0="__YOUR_SSH_PUB_KEY__"
```

## Example logs

Below it's possible to find an example log produced by cluster-node-init running in systemd, it's from a node that has already performed the first boot.

```
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] cluster-node-init.sh v0.1
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] Daniele Albano <d.albano@gmail.com>
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] ---
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] The modules directory path is </opt/cluster-node-init/modules.d>
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] The config file path is </opt/cluster-node-init/config.env>
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] Loading configuration
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] Configuration loaded
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] Searching modules < remove-cloud-init hostname-configure disks-configure timezone-configure keep-vt-logs-console network-configure apt-configure apt-update apt-upgrade apt-install-packages snap-install-packages ntp-configure apparmor-disable sshd-configure users-configure print-info>
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: /opt/cluster-node-init/cluster-node-init.sh: line 93: `$MODULE_NAME': not a valid identifier
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] All requested modules are available
Jan 10 00:05:58 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:58 2021][INFO] Starting <remove-cloud-init>, retry <1> of <3>
Jan 10 00:05:58 localhost cluster-node-init.sh[1696]: [Sun Jan 10 00:05:58 2021][INFO][remove-cloud-init] Removing the <cloud-init> package
Jan 10 00:05:59 localhost cluster-node-init.sh[1711]: dpkg: warning: ignoring request to remove cloud-init which isn't installed
Jan 10 00:05:59 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:59 2021][INFO] Module executed successfully
Jan 10 00:05:59 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:05:59 2021][INFO] Starting <hostname-configure>, retry <1> of <3>
Jan 10 00:05:59 localhost cluster-node-init.sh[1721]: [Sun Jan 10 00:05:59 2021][INFO][hostname-configure] Running cmd <echo 'rpi4-3f4f044e'> to determine hostname
Jan 10 00:05:59 localhost cluster-node-init.sh[1721]: [Sun Jan 10 00:05:59 2021][INFO][hostname-configure] Current hostname matches <rpi4-3f4f044e>, don't update the current configuration
Jan 10 00:05:59 localhost cluster-node-init.sh[1770]: RTNETLINK answers: File exists
Jan 10 00:06:00 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:00 2021][INFO] Module executed successfully
Jan 10 00:06:00 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:00 2021][INFO] Starting <disks-configure>, retry <1> of <3>
Jan 10 00:06:00 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:00 2021][INFO][disks-configure] Creating new partition of size <4G> and type <swap> on </dev/sda>
Jan 10 00:06:00 localhost cluster-node-init.sh[1843]: Partition #1 contains a swap signature.
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Partition created
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Creating filesystem <swap> with UUID <3bbc3ae1-18b4-4f89-9b73-c55c70b9c1d0> on </dev/sda1>
Jan 10 00:06:01 localhost cluster-node-init.sh[1872]: mkswap: /dev/sda1: warning: wiping old swap signature.
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Filesystem created
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Adding </dev/sda1> with UUID <3bbc3ae1-18b4-4f89-9b73-c55c70b9c1d0> to /etc/fstab
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Activating swap for </dev/sda1> with UUID <3bbc3ae1-18b4-4f89-9b73-c55c70b9c1d0>
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Swap activated
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Creating new partition of size <all> and type <ext4> on </dev/sda>
Jan 10 00:06:01 localhost cluster-node-init.sh[1917]: Partition #2 contains a ext4 signature.
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Partition created
Jan 10 00:06:01 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:01 2021][INFO][disks-configure] Creating filesystem <ext4> with UUID <b25161e9-a64e-4779-8452-a132bd26b800> on </dev/sda2>
Jan 10 00:06:01 localhost cluster-node-init.sh[1927]: mke2fs 1.45.6 (20-Mar-2020)
Jan 10 00:06:03 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:03 2021][INFO][disks-configure] Filesystem created
Jan 10 00:06:03 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:03 2021][INFO][disks-configure] Adding </dev/sda2> with UUID <b25161e9-a64e-4779-8452-a132bd26b800> to /etc/fstab
Jan 10 00:06:03 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:03 2021][INFO][disks-configure] Mounting </mnt/data> with UUID <b25161e9-a64e-4779-8452-a132bd26b800>
Jan 10 00:06:03 localhost cluster-node-init.sh[1802]: [Sun Jan 10 00:06:03 2021][INFO][disks-configure] Mounted
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Module executed successfully
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Starting <timezone-configure>, retry <1> of <3>
Jan 10 00:06:03 localhost cluster-node-init.sh[1972]: [Sun Jan 10 00:06:03 2021][INFO][timezone-configure] TODO
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Module executed successfully
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Starting <keep-vt-logs-console>, retry <1> of <3>
Jan 10 00:06:03 localhost cluster-node-init.sh[1983]: [Sun Jan 10 00:06:03 2021][INFO][keep-vt-logs-console] The parameter <TTYVTDisallocate> for <getty@tty1> is already set to <no>
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Module executed successfully
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Starting <network-configure>, retry <1> of <3>
Jan 10 00:06:03 localhost cluster-node-init.sh[1996]: [Sun Jan 10 00:06:03 2021][INFO][network-configure] TODO
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Module executed successfully
Jan 10 00:06:03 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:03 2021][INFO] Starting <apt-configure>, retry <1> of <3>
Jan 10 00:06:03 localhost cluster-node-init.sh[2007]: [Sun Jan 10 00:06:03 2021][INFO][apt-configure] TODO
Jan 10 00:06:04 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:04 2021][INFO] Module executed successfully
Jan 10 00:06:04 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:04 2021][INFO] Starting <apt-update>, retry <1> of <3>
Jan 10 00:06:04 localhost cluster-node-init.sh[2018]: [Sun Jan 10 00:06:04 2021][INFO][apt-update] Apt cache updated <9013> seconds ago
Jan 10 00:06:04 localhost cluster-node-init.sh[2018]: [Sun Jan 10 00:06:04 2021][INFO][apt-update] Skipping package cache update, last update less than <86400> seconds ago
Jan 10 00:06:04 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:04 2021][INFO] Module executed successfully
Jan 10 00:06:04 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:04 2021][INFO] Starting <apt-upgrade>, retry <1> of <3>
Jan 10 00:06:07 localhost cluster-node-init.sh[2040]: linux-image-raspi set on hold.
Jan 10 00:06:07 localhost cluster-node-init.sh[2040]: linux-headers-raspi set on hold.
Jan 10 00:06:07 localhost cluster-node-init.sh[2040]: linux-firmware set on hold.
Jan 10 00:06:07 localhost cluster-node-init.sh[2032]: [Sun Jan 10 00:06:07 2021][INFO][apt-upgrade] Installing updates (if any)
Jan 10 00:06:07 localhost cluster-node-init.sh[2049]: WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
Jan 10 00:06:09 localhost cluster-node-init.sh[2049]: Reading package lists...
Jan 10 00:06:10 localhost cluster-node-init.sh[2049]: Building dependency tree...
Jan 10 00:06:10 localhost cluster-node-init.sh[2049]: Reading state information...
Jan 10 00:06:10 localhost cluster-node-init.sh[2049]: Calculating upgrade...
Jan 10 00:06:11 localhost cluster-node-init.sh[2049]: 0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Jan 10 00:06:11 localhost cluster-node-init.sh[2032]: [Sun Jan 10 00:06:11 2021][INFO][apt-upgrade] Autoremoving old packages (if any)
Jan 10 00:06:11 localhost cluster-node-init.sh[2056]: WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
Jan 10 00:06:12 localhost cluster-node-init.sh[2056]: Reading package lists...
Jan 10 00:06:13 localhost cluster-node-init.sh[2056]: Building dependency tree...
Jan 10 00:06:13 localhost cluster-node-init.sh[2056]: Reading state information...
Jan 10 00:06:14 localhost cluster-node-init.sh[2056]: 0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Jan 10 00:06:15 localhost cluster-node-init.sh[2191]: Canceled hold on linux-image-raspi.
Jan 10 00:06:15 localhost cluster-node-init.sh[2191]: Canceled hold on linux-headers-raspi.
Jan 10 00:06:15 localhost cluster-node-init.sh[2191]: Canceled hold on linux-firmware.
Jan 10 00:06:15 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:15 2021][INFO] Module executed successfully
Jan 10 00:06:15 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:15 2021][INFO] Starting <apt-install-packages>, retry <1> of <3>
Jan 10 00:06:15 localhost cluster-node-init.sh[2199]: [Sun Jan 10 00:06:15 2021][INFO][apt-install-packages] Installing packages < mc nano redis-tools iperf3 iftop htop rng-tools python3-pip python3-pil python3-smbus python3-rpi.gpio python3-psutil i2c-tools fonts-freefont-ttf ifenslave build-essential cmake flex bison gdb autoconf automake gcc-9 g++-9 gdb gdbserver lcov ca-certificates libraspberrypi-bin>
Jan 10 00:06:15 localhost cluster-node-init.sh[2207]: WARNING: apt does not have a stable CLI interface. Use with caution in scripts.
Jan 10 00:06:17 localhost cluster-node-init.sh[2207]: Reading package lists...
Jan 10 00:06:17 localhost cluster-node-init.sh[2207]: Building dependency tree...
Jan 10 00:06:17 localhost cluster-node-init.sh[2207]: Reading state information...
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: autoconf is already the newest version (2.69-11.1).
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: automake is already the newest version (1:1.16.2-4ubuntu1).
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: bison is already the newest version (2:3.7+dfsg-1).
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: build-essential is already the newest version (12.8ubuntu3).
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: cmake is already the newest version (3.16.3-3ubuntu2).
Jan 10 00:06:18 localhost cluster-node-init.sh[2207]: flex is already the newest version (2.6.4-8).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: fonts-freefont-ttf is already the newest version (20120503-10).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: gdb is already the newest version (9.2-0ubuntu2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: gdbserver is already the newest version (9.2-0ubuntu2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: htop is already the newest version (3.0.2-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: nano is already the newest version (5.2-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: python3-pil is already the newest version (7.2.0-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: python3-psutil is already the newest version (5.7.2-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: g++-9 is already the newest version (9.3.0-18ubuntu1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: gcc-9 is already the newest version (9.3.0-18ubuntu1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: i2c-tools is already the newest version (4.1-2build2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: ifenslave is already the newest version (2.10ubuntu3).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: iftop is already the newest version (1.0~pre4-7).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: iperf3 is already the newest version (3.7-3).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: lcov is already the newest version (1.14-2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: libraspberrypi-bin is already the newest version (0~20200520+git2fe4ca3-0ubuntu2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: mc is already the newest version (3:4.8.25-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: python3-pip is already the newest version (20.1.1-2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: python3-rpi.gpio is already the newest version (0.7.0-0.2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: python3-smbus is already the newest version (4.1-2build2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: redis-tools is already the newest version (5:6.0.6-1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: rng-tools is already the newest version (5-1ubuntu2).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: ca-certificates is already the newest version (20201027ubuntu0.20.10.1).
Jan 10 00:06:19 localhost cluster-node-init.sh[2207]: 0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:18 2021][INFO] Module executed successfully
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:18 2021][INFO] Starting <snap-install-packages>, retry <1> of <3>
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Module executed successfully
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Starting <ntp-configure>, retry <1> of <3>
Jan 10 00:06:19 localhost cluster-node-init.sh[2260]: [Sun Jan 10 00:06:19 2021][INFO][ntp-configure] TODO
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Module executed successfully
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Starting <apparmor-disable>, retry <1> of <3>
Jan 10 00:06:19 localhost cluster-node-init.sh[2278]: [Sun Jan 10 00:06:19 2021][VERBOSE][apparmor-disable] The service <apparmor> is not running
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Module executed successfully
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Starting <sshd-configure>, retry <1> of <3>
Jan 10 00:06:19 localhost cluster-node-init.sh[2285]: [Sun Jan 10 00:06:19 2021][INFO][sshd-configure] SSH daemon host keys already existing, nothing to do
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Module executed successfully
Jan 10 00:06:19 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:19 2021][INFO] Starting <users-configure>, retry <1> of <3>
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] User <daalbano> already existing, skipping creation but syncing settings
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] Shell </bin/bash> requested
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] User additional groups set to <adm,audio,cdrom,dialout,dip,floppy,lxd,netdev,plugdev,sudo,video>
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] Syncing user settings
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] User settings synced
Jan 10 00:06:19 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:19 2021][INFO][users-configure] Sudo NOPASSWD flag for the user already set, skipping
Jan 10 00:06:20 localhost cluster-node-init.sh[2299]: [Sun Jan 10 00:06:20 2021][INFO][users-configure] User <daalbano> has already auth key <0>, skipping creation
Jan 10 00:06:20 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:20 2021][INFO] Module executed successfully
Jan 10 00:06:20 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:20 2021][INFO] Starting <print-info>, retry <1> of <3>
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] Hostname
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > rpi4-3f4f044e
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info]
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] IP Address(es)
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > eth0
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] * 192.168.255.115/24
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] * fe80::dea6:32ff:fec3:c14/64
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info]
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] SSH host keys
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > ssh_host_ecdsa_key.pub
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > __HIDDEN__
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info]
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > ssh_host_ed25519_key.pub
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > __HIDDEN__
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info]
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > ssh_host_rsa_key.pub
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info] > __HIDDEN__
Jan 10 00:06:20 localhost cluster-node-init.sh[2335]: [Sun Jan 10 00:06:20 2021][INFO][print-info]
Jan 10 00:06:20 localhost cluster-node-init.sh[1626]: [Sun Jan 10 00:06:20 2021][INFO] Module executed successfully
```
