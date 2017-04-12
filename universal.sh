#!/bin/bash

if [ $EUID != 0 ]; then
	sudo "$0" "$@"
	exit $?
fi


temp_dir=.cac-setup
os_ubuntu=$temp_dir/ubuntu
os_centos=$temp_dir/centos
packman_apt=$temp_dir/apt-get
packman_yum=$temp_dir/yum

create_temp_directory() {

	if [ ! -d $temp_dir ]; then

		mkdir $temp_dir

		if grep -i -q "ubuntu" /etc/os-release; then
			touch $os_ubuntu
		elif grep -i -q "centos" /etc/os-release; then
			touch $os_centos
		else
			echo "Unsupported OS"
		fi

		if [ -n "$(command -v apt-get)" ]; then
			touch $packman_apt
		elif [ -n "$(command -v yum)" ]; then
			touch $packman_yum
		else
			echo "Unsupported Package Manager"
		fi

	fi

}

clear_temp_directory() {
	rm -rf $temp_dir
}

prepare_system() {

	if [ ! -f $os_centos ]; then

		# http://utdream.org/post.cfm/yum-couldn-t-resolve-host-mirrorlist-centos-org-for-centos-6
		echo "nameserver 8.8.8.8" >> /etc/resolv.conf
		echo "nameserver 8.8.4.4" >> /etc/resolv.conf
		echo "nameserver 127.0.0.1" >> /etc/resolv.conf

	fi

}

install_prerequisites() {

	if [ -f $packman_yum ]; then

		yum install yum-utils policycoreutils-python vim-common -y

	fi

}

upgrade_machine() {
	if [ -f $packman_apt ]; then
		apt-get update
		apt-get upgrade -y
		apt-get dist-upgrade -y
		apt-get autoremove -y
	elif [ -f $packman_yum ]; then
		yum update -y
	fi
}

update_machine_name() {
	echo "machine name [jeric]:"
	read machine_name

	if [[ -z "${machine_name// }" ]]; then
		machine_name=jeric
	fi

	if [ -f $os_ubuntu ]; then
		sed -i s/ubuntu/$machine_name/ /etc/hosts
		sed -i s/ubuntu/$machine_name/ /etc/hostname
		hostname $machine_name
	elif [ -f $os_centos ]; then
		hostnamectl set-hostname $machine_name
	fi
}

create_new_account() {

	echo "username:"
	read new_account
	echo "password:"
	read -s new_account_password

	# account update
	echo "change root password"
	echo "root:$new_account_password" | chpasswd
	echo "deleting default user"
	if [ -f $os_ubuntu ]; then
		deluser --remove-home user
	elif [ -f $os_centos ]; then
		userdel -r user
	fi
	

	echo "creating new user $new_account"
	if [ -f $os_ubuntu ]; then
		adduser --quiet --disabled-password --gecos "" $new_account
	elif [ -f $os_centos ]; then
		adduser $new_account
	fi

	echo "setting password for $new_account"
	echo "$new_account:$new_account_password" | chpasswd
	if [ -f $os_ubuntu ]; then
		adduser $new_account sudo
	elif [ -f $os_centos ]; then
		gpasswd -a $new_account wheel
	fi

}

cleanup_old_kernels__ubuntu() {

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

cleanup_old_kernels__centos() {
	package-cleanup --oldkernels --count=1 -y
}

cleanup_old_kernels() {

	# clean up old kernels

	echo
	echo "=========================================="
	echo "cleaning up old kernels..."
	echo "=========================================="
	echo

	if [ -f $os_ubuntu ]; then
		cleanup_old_kernels__ubuntu
	elif [ -f $os_centos ]; then
		cleanup_old_kernels__centos
	fi

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
		if [ -f $os_ubuntu ]; then
			ssh-keygen -E sha256 -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
			ssh-keygen -E md5 -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
		elif [ -f $os_centos ]; then
			awk '{print $2}' /etc/ssh/ssh_host_"$ssh_key_type"_key.pub | base64 -d | sha256sum -b | awk '{print $1}' | xxd -r -p | base64
			ssh-keygen -lf /etc/ssh/ssh_host_"$ssh_key_type"_key
		fi

	done
}

configure_ssh() {

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

	if [ -f $os_centos ]; then
		echo "running semanage..."
		semanage port -a -t ssh_port_t -p tcp $ssh_port
	fi

	echo "creating new ssh server keys..."
	regenerate_ssh_server_keys


}



create_temp_directory
prepare_system

if [ ! -f $temp_dir/kernel_remove_ready ]; then

	install_prerequisites

	echo "=========================================="
	echo "basic information"
	echo "=========================================="
	echo

	update_machine_name

	create_new_account

	echo
	echo "=========================================="
	echo "upgrading to latest version before doing a release upgrade..."
	echo "=========================================="
	echo

	# upgrade everything before release upgrade
	upgrade_machine

	touch $temp_dir/kernel_remove_ready
	echo "press any key to reboot machine, rerun script after rebooting"
	read confirm_key
	reboot -h now
	exit

fi


if [ ! -f $temp_dir/release_upgrade_done ]; then

	cleanup_old_kernels

	if [ -f $os_ubuntu ]; then
		# manually select upgrade options (important)

		echo
		echo "=========================================="
		echo "begin release upgrade..."
		echo "=========================================="
		echo

		do-release-upgrade

		touch $temp_dir/release_upgrade_done
		echo "press any key to reboot machine, rerun script after rebooting"
		read confirm_key
		reboot -h now
		exit
	fi

	touch $temp_dir/release_upgrade_done

fi


if [ -f $os_ubuntu ]; then

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

fi


clear_temp_directory

configure_ssh

echo
echo "=========================================="
echo "System is Ready"
echo "=========================================="
echo
echo "press any key to reboot machine"
read confirm_key
reboot -h now


