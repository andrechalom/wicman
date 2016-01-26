# wicman - a minimalistic WIreless Connection MANager

wicman is a minimalistic wireless connection manager,
intended to be light-weight, with few dependencies, 
and implement command-line access to wireless networks.

wicman should NOT be used side-by-side with other connection
managers such as NetworkManager, wicd, connman. Stop and disable
these connection managers before starting wicman

# Depends:
wicman depends on ruby (tested on 1.9.3), wpa_supplicant, iwlist
and ifconfig. You can install these with:
```
sudo apt-get install ruby wpasupplicant wireless-tools net-tools
```

# Features:
- FULL Command-line control
- List available connections
- Connect to hidden network
- Persistent and safe storage of authentication keys
- Configurable list of preferences for ranking connections
- Autoconnect on connection dropped (TODO)
- Check for internet connection and switch to other available networks
  in case of router failure. (TODO)

# How to install
On Debian/Ubuntu, simply run ./install.sh. Then use wicman -h to display
the help.

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

# TO DO:
- stop passphrase from being written to disk
- make an option for "show connection status"
- health checks (autoconnect if dropped, change nets if 8.8.8.8 is unreachable)
- extensions (iw instead of iwlist, dhcpd instead of dhclient, etc)
- tidy up install.sh
- option to sort list by Name or Strenght?
- start w/o config file using reasonable defaults?
