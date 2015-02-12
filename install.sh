#!/bin/sh
echo "Copying files to /etc"
cp -v wicmand.conf /etc/wicmand.conf
cp -v wicmand.sysv /etc/init.d/wicmand
echo "Copying files to /usr/bin"
cp -v wicmand.rb /usr/sbin/wicmand
cp -v wicman.rb /usr/bin/wicman
echo "Configuring Sys V init"
update-rc.d wicmand defaults
service wicmand start
