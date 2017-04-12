#!/bin/bash

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	exit $?
fi

prepare_system() {
	# http://utdream.org/post.cfm/yum-couldn-t-resolve-host-mirrorlist-centos-org-for-centos-6
	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	echo "nameserver 8.8.4.4" >> /etc/resolv.conf
	echo "nameserver 127.0.0.1" >> /etc/resolv.conf
}

install_prerequisites() {
	yum install yum-utils policycoreutils-python -y
}

upgrade_machine() {
	yum update -y
}

cleanup_old_kernels() {

	# clean up old kernels

	echo
	echo "=========================================="
	echo "cleaning up old kernels..."
	echo "=========================================="
	echo

	package-cleanup --oldkernels --count=1 -y

}

regenerate_ssh_server_keys() {
	mapfile -t ssh_key_types < <(ls -l /etc/ssh | grep .pub | awk '{print $9}' | sed -r 's/ssh_host_([a-zA-Z0-9]+)_key.pub/\1/')

	echo "new ssh server keys:"

	for ssh_key_type in "${ssh_key_types[@]}"
	do
		rm /etc/ssh/ssh_host_"$ssh_key_type"_key
		rm /etc/ssh/ssh_host_"$ssh_key_type"_key.pub

		ssh-keygen -q -N "" -t $ssh_key_type -f  /etc/ssh/ssh_host_"$ssh_key_type"_key

		echo
		echo $ssh_key_type | awk '{print toupper($1)}'
		awk '{print $2}' /etc/ssh/ssh_host_"$ssh_key_type"_key.pub | base64 -d | sha256sum -b | awk '{print $1}' | xxd -r -p | base64
		ssh-keygen -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
	done
}

if [ ! -f .kernel_remove_ready ]; then

	prepare_system

	echo "=========================================="
	echo "basic information"
	echo "=========================================="
	echo
	echo "machine name [centos]:"
	read machine_name

	if [[ -z "${machine_name// }" ]]; then
		machine_name=centos
	fi

	hostnamectl set-hostname $machine_name

	echo "username:"
	read new_account
	echo "password:"
	read -s new_account_password

	# account update
	echo "change root password"
	echo "root:$new_account_password" | chpasswd
	echo "deleting default user"
	userdel -r user

	echo "creating new user $new_account"
	adduser $new_account
	echo "setting password for $new_account"
	echo "$new_account:$new_account_password" | chpasswd
	gpasswd -a $new_account wheel

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

	prepare_system
	install_prerequisites

	cleanup_old_kernels

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

#upgrade_machine

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
sed -i "s/#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/#PermitRootLogin no/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config

echo "new ssh port [22]:"
read ssh_port

if [[ -z "${ssh_port// }" ]]; then
	ssh_port=22
fi

sed -i "s/#Port 22/Port 22/" /etc/ssh/sshd_config
sed -i "s/Port 22/Port $ssh_port/" /etc/ssh/sshd_config
semanage port -a -t ssh_port_t -p tcp $ssh_port


echo "creating new ssh server keys..."
regenerate_ssh_server_keys

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


