#!/bin/bash

echo "" > /etc/apt/sources.list.d/redis.list || echo "Failed to reset Redis repository configuration."

echo "deb http://archive.ubuntu.com/ubuntu focal main universe" >> /etc/apt/sources.list.d/redis.list || echo "Failed to add Redis repository."

echo "------------------"
echo "Changing Password"
echo "------------------"
PASSWORD=$(openssl rand -base64 12)
echo root:$PASSWORD | chpasswd && echo "Password changed to: $PASSWORD" || echo "Failed to change password."
echo

echo "------------------"
echo "Installing GRUB"
echo "------------------"
if grub-install /dev/sda; then
    echo "GRUB installed on /dev/sda."
else
    echo "Failed to install GRUB on /dev/sda."
fi
if grub-install /dev/sdb; then
    echo "GRUB installed on /dev/sdb."
else
    echo "Failed to install GRUB on /dev/sdb."
fi
echo

echo "------------------"
echo "Checking RAID Status"
echo "------------------"
cat /proc/mdstat || echo "Failed to check RAID status."
echo

echo "------------------"
echo "Testing Nginx Configuration"
echo "------------------"
nginx -t || echo "Nginx configuration test failed."
echo

echo "------------------"
echo "Listing Nginx Sites"
echo "------------------"
if [ -d "/etc/nginx/sites-enabled/" ]; then
    ls -lahr /etc/nginx/sites-enabled/ || echo "Failed to list Nginx sites."
else
    echo "Nginx sites-enabled directory does not exist."
fi
echo

echo "------------------"
echo "Checking Service Status"
echo "------------------"
services=("nginx" "mysql" "elasticsearch" "varnish")
for service in "${services[@]}"; do
    echo -n "Checking $service: "
    systemctl is-active $service && systemctl is-enabled $service || echo "$service is inactive or not enabled."
done

echo "Checking for enabled PHP-FPM versions:"
php_fpm_services=$(systemctl list-unit-files | grep 'php.*fpm.service' | awk '{print $1}')
for php_service in $php_fpm_services; do
    echo "$php_service is enabled."
    if systemctl is-active $php_service > /dev/null; then
        echo "$php_service is active."
    else
        echo "$php_service is not active."
        systemctl status $php_service --no-pager | head -n 10
    fi
done
echo

echo "------------------"
echo "Checking Mounted NFS Filesystems"
echo "------------------"
mount | grep 'type nfs' || echo "No NFS filesystems are currently mounted."
echo

echo "------------------"
echo "Checking NFS Entries in fstab"
echo "------------------"
grep nfs /etc/fstab || echo "No NFS entries found in /etc/fstab."
echo

echo "Please enter the server type (Master, Sql, Node):"
read SERVER_TYPE

echo "------------------"
echo "Updating packages and managing holds..."
echo "------------------"
apt-mark showhold || { echo "Failed to list held packages."; exit 1; }

# Blanket check for installed packages before attempting to unhold
for package in "mysql" "mariadb" "percona" "elasticsearch" "varnish"; do
    if dpkg-query -W --showformat='${Status}\n' $package 2>/dev/null | grep "install ok installed"; then
        apt-mark unhold $(apt-mark showhold | grep -vE "$package") || { echo "Failed to unhold $package package."; }
    else
        echo "$package package is not installed. Skipping unhold."
    fi
done

apt-mark hold mysql* mariadb* percona* elasticsearch* varnish* || { echo "Failed to hold specified packages."; exit 1; }
apt-get update || { echo "Failed to update packages."; exit 1; }
apt-get upgrade -y || { echo "Failed to upgrade packages."; exit 1; }

echo "Dumping firewall rules..."
iptables-save > /root/iptables.save || { echo "Failed to dump firewall rules."; exit 1; }
echo
