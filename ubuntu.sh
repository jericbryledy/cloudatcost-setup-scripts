#!/bin/bash

upgrade_machine() {
	apt-get update
	apt-get upgrade -y
	apt-get dist-upgrade -y
	apt-get autoremove -y
}

cleanup_old_kernels() {

	# clean up old kernels

	echo
	echo "=========================================="
	echo "cleaning up old kernels..."
	echo "=========================================="
	echo

	mapfile -t kernels < <(dpkg -l | tail -n +6 | grep -E 'linux-image-[0-9]+' | grep -Fv $(uname -r) | awk '{print $2}' | sed s/-generic//)

	for kernel in "${kernels[@]}"
	do
		echo "=========================================="
		echo "removing $kernel"
		echo "=========================================="
		sudo dpkg --purge $kernel-generic
		sudo dpkg --purge $kernel-header $kernel
	done


	echo
	echo "=========================================="
	echo "deleting old linux images from boot partition..."
	echo "=========================================="
	echo

	ls /boot | grep "\-generic" | grep -Fv $(uname -r) | awk '{print "/boot/" $1}' | xargs rm

}

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	exit $?
fi

if [ ! -f .kernel_remove_ready ]; then

	echo "=========================================="
	echo "basic information"
	echo "=========================================="
	echo
	echo "machine name [ubuntu]:"
	read machine_name

	if [[ -z "${machine_name// }" ]]; then
		machine_name=ubuntu
	fi

	sed -i s/ubuntu/$machine_name/ /etc/hosts
	sed -i s/ubuntu/$machine_name/ /etc/hostname
	hostname $machine_name

	echo "username:"
	read new_account
	echo "password:"
	read -s new_account_password

	# account update
	echo "change root password"
	echo "root:$new_account_password" | chpasswd
	echo "deleting default user"
	deluser --remove-home user

	echo "creating new user $new_account"
	adduser --quiet --disabled-password --gecos "" $new_account
	echo "setting password for $new_account"
	echo "$new_account:$new_account_password" | chpasswd
	adduser $new_account sudo

	echo
	echo "=========================================="
	echo "upgrading to latest version before doing a release upgrade..."
	echo "=========================================="
	echo

	# upgrade everything before release upgrade
	upgrade_machine

	touch .kernel_remove_ready
	echo "press any key to reboot machine, rerun script after rebooting"
	read confirm_key
	reboot -h now
	exit

fi



if [ ! -f .release_upgrade_done ]; then

	cleanup_old_kernels

	# manually select upgrade options (important)

	echo
	echo "=========================================="
	echo "begin release upgrade..."
	echo "=========================================="
	echo

	do-release-upgrade

	touch .release_upgrade_done
	echo "press any key to reboot machine, rerun script after rebooting"
	read confirm_key
	reboot -h now
	exit

fi



cleanup_old_kernels

# check for newer updates

echo
echo "=========================================="
echo "check for further updates..."
echo "=========================================="
echo

upgrade_machine

echo
echo "=========================================="
echo "cleaning up temporary files..."
echo "=========================================="
echo

rm .kernel_remove_ready
rm .release_upgrade_done


echo
echo "=========================================="
echo "Configuring SSH..."
echo "=========================================="
echo

echo "disabling root login..."
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config

echo "new ssh port [22]:"
read ssh_port

if [[ -z "${ssh_port// }" ]]; then
	ssh_port=22
fi

sed -i "s/Port 22/Port $ssh_port/" /etc/ssh/sshd_config


echo "restarting ssh..."
service ssh restart

echo
echo "=========================================="
echo "System is Ready"
echo "=========================================="
echo
echo "press any key to reboot machine"
read confirm_key
reboot -h now


