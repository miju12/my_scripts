#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2018 Harsh 'MSF Jarvis' Shandilya
# Copyright (C) 2018 Akhil Narang

# Script to set up an AOSP build environment on Ubuntu and Linux Mint

# Variables
LATEST_MAKE_VERSION="4.3"
UBUNTU_16_PACKAGES="libesd0-dev"
UBUNTU_20_PACKAGES="libncurses5 curl python-is-python3"
DEBIAN_10_PACKAGES="libncurses5"
DEBIAN_11_PACKAGES="libncurses5"
PACKAGES=""

# Functions
update_and_install() {
    sudo apt update
    sudo apt install "$@" -y
}

# Main Script
echo "Updating package lists and installing initial packages..."
update_and_install software-properties-common lsb-core

LSB_RELEASE="$(lsb_release -d | awk -F: '{print $2}' | sed -e 's/^[[:space:]]*//')"

case $LSB_RELEASE in
    *"Mint 18"* | *"Ubuntu 16"*)
        PACKAGES=$UBUNTU_16_PACKAGES
        ;;
    *"Ubuntu 20"* | *"Ubuntu 21"* | *"Ubuntu 22"* | *"Pop!_OS 2"*)
        PACKAGES=$UBUNTU_20_PACKAGES
        ;;
    *"Debian GNU/Linux 10"*)
        PACKAGES=$DEBIAN_10_PACKAGES
        ;;
    *"Debian GNU/Linux 11"*)
        PACKAGES=$DEBIAN_11_PACKAGES
        ;;
esac

echo "Installing required packages..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    adb autoconf automake axel bc bison build-essential \
    ccache clang cmake curl expat fastboot flex g++ \
    g++-multilib gawk gcc gcc-multilib git git-lfs gnupg gperf \
    htop imagemagick lib32ncurses5-dev lib32z1-dev libtinfo5 libc6-dev libcap-dev \
    libexpat1-dev libgmp-dev '^liblz4-.*' '^liblzma.*' libmpc-dev libmpfr-dev libncurses5-dev \
    libsdl1.2-dev libssl-dev libtool libxml2 libxml2-utils '^lzma.*' lzop \
    maven ncftp ncurses-dev patch patchelf pkg-config pngcrush \
    pngquant python2.7 python3-pyelftools python-all-dev re2c schedtool squashfs-tools subversion \
    texinfo unzip w3m xsltproc zip zlib1g-dev lzip \
    libxml-simple-perl libswitch-perl apt-utils rsync \
    $PACKAGES

echo "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
update_and_install gh

echo "Setting up udev rules for adb..."
sudo curl --create-dirs -L -o /etc/udev/rules.d/51-android.rules https://raw.githubusercontent.com/M0Rf30/android-udev-rules/master/51-android.rules
sudo chmod 644 /etc/udev/rules.d/51-android.rules
sudo chown root:root /etc/udev/rules.d/51-android.rules
sudo systemctl restart udev

if [[ "$(command -v make)" ]]; then
    makeversion="$(make -v | head -1 | awk '{print $3}')"
    if [[ $makeversion != $LATEST_MAKE_VERSION ]]; then
        echo "Installing make $LATEST_MAKE_VERSION instead of $makeversion"
        bash "$(dirname "$0")/make.sh" "$LATEST_MAKE_VERSION"
    fi
fi

echo "Installing repo tool..."
sudo curl --create-dirs -L -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
sudo chmod a+rx /usr/local/bin/repo

echo "Configuring Git..."
read -p "Enter your Git user name: " git_user_name
read -p "Enter your Git email: " git_email
git config --global user.name "$git_user_name"
git config --global user.email "$git_email"

echo "Generating a new SSH key using the configured Git email..."
ssh-keygen -t rsa -b 4096 -C "$git_email"

echo "Your new SSH public key is:"
cat ~/.ssh/id_rsa.pub

echo "AOSP build environment setup complete!"
