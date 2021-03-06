# wicman - a minimalistic WIreless Connection MANager

wicman is a minimalistic wireless connection manager,
intended to be light-weight, with few dependencies, 
and implement command-line access to wireless networks.

wicman should NOT be used side-by-side with other connection
managers such as NetworkManager, wicd, connman. Stop and disable
these connection managers before starting wicman

# Depends:
wicman depends on ruby (tested on 1.9.3), wpa_supplicant, iwlist from package wireless-tools
and ifconfig/route from net-tools. You can install these with:
```
sudo apt-get install ruby wpasupplicant wireless-tools net-tools
```

# Features:
- FULL Command-line control
- List available connections
- Connect to hidden network
- Persistent and safe storage of authentication keys
- Configurable list of preferences for ranking connections
- Autoconnect on connection dropped
- Check for internet connection and switch to other available networks
  in case of router failure. (TODO)

# How to install
First, edit the wicman.conf configuration file to match your needs:
the most important are the interface to use, by default wlan0, and
whether or not to use autoconnect on connection dropped (use reconnect: 0 
to disable).

On Debian/Ubuntu, simply run ./install.sh to copy the files to /etc and /usr.
For other distributions, copy the files to the required locations, and edit
the configuration files and init scripts to match.

Then use wicman -h to display the help.

# Why?

The most popular command line connection manager is [wicd] (https://launchpad.net/wicd),
but it had a long development hiatus in 2012-2014. During this time, I
have started development on an alternative that did not have the bugs
that were reported in wicd. The project has continued focused on having minimal
requirements and low resource usage.

wicman is intended as a small wrapper for wpa_supplicant, which does the 
heavy work of actually connecting to the wireless networks. It provides
only basic functionality, inspired by the KISS philosophy (Keep it Simple
and Straightforward). For instance, DNS servers are managed by 
/etc/resolv.conf, dhcp configurations are managed by dhclient.conf,
and there is no provision for managing these options inside wicman.
