#! /bin/bash

sudo_prefix=""
docker_packages="install docker docker.io apparmor cgroup-lite"

if [ "${USER}" != "root" ]; then
    read -p "apt and usermod commands might require root right, do you want to use sudo to run them ? [Y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo "Using sudo"
        sudo_prefix="sudo"
    else
        echo "Skipped"
    fi
fi

echo "Installing the following packages : $docker_packages"
$sudo_prefix apt-get install $docker_packages || (echo "Process failed" && exit 1)

read -p "Do you want to add the current user to docker group ? [Y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Adding user ${USER} to docker group"
    $sudo_prefix usermod -a -G docker $USER || (echo "Process failed" && exit 1)
else
    echo "Skipped"
fi
