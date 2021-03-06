#!/usr/bin/env ruby
# This file contains the wicman daemon that should be running
# as root on the background. wicman command-line interface
# will connect to this daemon to perform actions

require 'yaml'
require 'optparse'
require 'open3'
require 'digest'
require 'socket'
require 'timeout'

Version = "1.0.0"

# Parses command line arguments
options = {}
optparse = OptionParser.new do |opts|
    opts.banner = "wicman daemon version #{Version}\nUsage:"
    options[:verbose] = false
    opts.on( '-v', '--verbose', 'Output more information' ) do
        options[:verbose] = true
    end
    options[:configfile] = "/etc/wicmand.conf"
    opts.on( '-f', '--configfile FILE', 'Use alternate configuration file' ) { |file|
        options[:configfile] = file
    }
    options[:daemon] = true
    opts.on( '-n', '--no_daemon', 'Don\'t run as a daemon','(runs in the foreground)' ) {
        options[:daemon] = false
    }
    options[:status] = false
    opts.on( '-s', '--status', 'Shows only the daemon running status' ) {
        options[:status] = true
    }
    options[:kill] = false
    opts.on( '-k', '--kill', 'Force closes an active instance of wicmand' ) {
        options[:kill] = true
    }
    opts.on( '-h', '--help', 'Display this screen' ) {
        puts opts
        exit
    }
end
optparse.parse!

# Handles the "--kill" option, which is not related to the core wicman
if options[:kill] then # If --kill was given, kill the active instance
    if options[:status]
        puts "Options --kill and --status are mutually exclusive, choose one"
        exit
    end
    puts "Ending all active wicmand processes"
    `pkill -HUP -f wicmand`
    exit
end 

class Wicmand
    ########## Functions related to managing the wicmand life cycle: daemon status, kill, managing pids
    # Helper function to open a file, read a single number and exit
    def get_number (file)
        File.open(file) { |f| return f.gets.chomp }
    end
    def clean_exit
        puts "wicmand exiting...\n"
        disconnect!
        Process.kill 9, @monitor unless @monitor.nil?
        Process.wait @monitor unless @monitor.nil?
        File.delete(pidfile) rescue nil
        exit
    end
    def daemonStatus
        if File.exists?(pidfile)
            Open3.popen3('ps', '-p', get_number(pidfile)) { |i,o,e,t|
                o.gets; line = o.gets # gets the second line
                if line =~/ruby/ 
                    puts "wicmand is up"
                    exit
                end
            }
        end
        puts "wicmand is down"
        exit
    end
    def pidfile (str = "wicmand")
        File.join(@config["varlib"],"#{str}.pid")
    end
    def pidMan #Manages pid-related and signals
        Process.daemon(nil, true) if @options[:daemon]
        Signal.trap("SIGHUP") {clean_exit} 
        Signal.trap("SIGINT") {clean_exit} 
        # else check for an instance, and start
        if File.exists?(pidfile)
            puts "WARNING: wicmand pid file found." 
            `kill -HUP #{get_number(pidfile)}`
            sleep(2)
        end
        File.open(pidfile, 'w') { |f| f.puts Process.pid }
    end
    ########### Initialization code
    def initialize(options = {}) 
        raise 'wicmand must run as root' unless Process.uid == 0
        @options = options
        @config = YAML.load_file(@options[:configfile])
        @connected = nil
        setupDirs
        daemonStatus if @options[:status]
        pidMan

        @interface = @config["interface"]
        puts "wicmand #{Version} starting..."
        setCache
        autoConnect
        setupMonitor # monitor will try to autoconnect if droped
        setupListener  # must be the LAST THING done by initialize as it never returns
    end
    ########## Code related to actual network management
    def setupMonitor
        pid = fork
        if pid.nil?
            exit if @config["reconnect"] == 0
            sfile = File.join(@config["temp"], "wicmand.socket")
            loop {
                sleep @config["reconnect"].to_i
                # Are we purposefuly disconnected?
                client = UNIXSocket.new sfile
                client.write "cname\n"
                status = client.gets
                if !status.nil?
                    ping = getPing(@config["internet"])
                    if ping == 0
                        client = UNIXSocket.new sfile
                        client.write "conn \"\" \"\"\n" 
                        status = client.gets
                    end
                end
                client.close
            }
        end
        @monitor = pid
    end
    def ifup
        puts "configuring interface #{@interface}" if @options[:verbose]
        Open3.popen3('ifconfig', @interface, 'up') { |i,o,e,t|
            raise "Error configuring interface #{@interface}!\nCheck that the interface exists" unless t.value == 0
        }
    end
    def getrouter
        Open3.popen3('route', '-n') { |i,o,e,t|
            while line = o.gets
                if line =~ /^0.0.0.0\s*([\d.]*).*#{@interface}/
                    return $1
                end
            end
        }
    end
    def getPing (ip)
        return 0 if ip.nil?
        Open3.popen3('ping', '-n', '-c 3', '-w 2', '-i 0.2', ip) { |i,o,e,t|
            i = 0
            while output = o.gets
                if / \d*\.\d*\/(\d*\.\d*)/ =~ output ## ONLY matches the summary line
                    return $1.to_f
                end
            end
            return 0
        }
    end
    def healthCheck
        @router_ping = getPing(@route)
        @internet_ping = getPing(@config["internet"])
        r = "Router: #{@route}\n"
        if @router_ping >0 
            r << "Router ping: #{@router_ping} ms\n"
        else
            r << "Router unreachable.\n"
        end
        if @internet_ping > 0 
            r << "Internet ping: #{@internet_ping} ms\n"
        else
            r << "Internet unreachable\n"
        end
        return r
    end
    # Creates a listening socket for client connections
    def setupListener
        sfile = File.join(@config["temp"], "wicmand.socket")
        File.unlink(sfile) rescue nil;
        @socket = UNIXServer.new(sfile)
        File.chmod(0666, sfile)
        while true
            begin
                client = @socket.accept
                conn = client.gets.chomp
                case conn
                when /^disc/
                    client.write disconnect!
                when /^conn "(.*)" "(.*)"/ 
                    if $1 == "" then
                        # No ESSID, should autoconnect
                        client.write autoConnect
                    elsif $2 != "" then
                        # Forcing new passphrase
                        status = genConfig($1, $2)
                        if status != "Configuration ok"
                            client.write status # Some error
                        else
                            client.write connect!($1)
                        end
                    else
                        # normal connection; if this fails tries to generate conf
                        status = connect!($1)
                        if status == "needconf"
                            client.write "needpp"
                        else
                            client.write status # Error or success message
                        end
                    end
                when /^auto "(.*)" "(.*)" (\d*)/ 
                    client.write addToAC($1, $3)
                when /^xauto "(.*)" "/ 
                    client.write dropFromAC($1)
                when /^conf "(.*)" "(.*)"/
                    client.write genConfig($1, $2)
                when /^list/
                    client.write getNetworks
                when /^show/
                    client.write showStatus
                when /^cname/ 
                    client.write @connected
                else
                    client.write "Your request is unsupported: #{conn}"
                end
                client.close
            rescue
                client.write "wicmand encountered an internal error"
                client.close
            end 
        end 
    end
    # Hashes the ESSID to make sure we don't do anything funny on the filesystem
    def configFile(essid)
        File.join(@config["varlib"], Digest::MD5.hexdigest(essid))
    end
    # Generates the wpa configuration file for an essid/passphrase and stores it in varlib
    def genConfig(essid, passphrase)
        puts "Generating configuration for #{essid}" if @options[:verbose]
        return "needpp" if passphrase == ""
        Open3.popen3('wpa_passphrase', essid, passphrase) { |i,o,e,t|
            return "Error generating configuration for ESSID #{essid}\nCheck that wpa_supplicant is installed" unless t.value == 0
            File.open(configFile(essid), 'w') { |f| 
                output = o.gets(nil)
                output.each_line { |l| 
                    unless @config["safe"] and l =~ /^\s*\#psk/ then
                        f.puts l
                    end
                }
            }
        }
        return "Configuration ok"
    end
    # Creates and ensures permission/ownership of the /var/lib directory used to store config
    def setupDirs
        puts "configuring varlib directory..." if @options[:verbose]
        raise "Malformed configuration file" if @config["varlib"].nil?
        Dir.mkdir(@config["varlib"], 0700) unless Dir.exists?(@config["varlib"])
        File.chown(0, 0, @config["varlib"])
        File.chmod(0700, @config["varlib"])
    end
    # Puts interface down and disconnects
    def disconnect!
        puts "Disconnecting from all networks!" if @options[:verbose]
        `pkill wpa_supplicant`
        `pkill dhclient`
        @connected = nil
        return "Disconnected"
    end
    # Attempts to connect to a given network. BLOCKING
    def connect!(essid)
        return "needconf" unless File.exists?(configFile(essid))
        disconnect!
        puts "Connecting to #{essid}" if @options[:verbose]
        pid = fork {
            ifup
            Open3.popen3('wpa_supplicant','-B', '-i', @interface, '-c', configFile(essid)) { |i,o,e,t|
                return "Error aquiring network #{essid}!\nCheck that the passphrase configured is correct" unless t.value == 0
            }
            sleep(2)
            Open3.popen3('dhclient', @interface) { |i, o, e, t|
                return "Error aquiring IP from network #{essid}!" unless t.value == 0
            }
            puts "Connection established" if @options[:verbose]
        }
        begin Timeout.timeout(20) do
            Process.wait
            @connected = essid
            @route = getrouter()
            return "Connected to #{essid}"
        end
        rescue Timeout::Error
            Process.kill 9, pid
            # collect status so it doesn't stick around as zombie process
            Process.wait pid
            puts "Unable to connect after 20 seconds, giving up!" if @options[:verbose]
            return "Unable to connect after 20 seconds, giving up!"
        end
    end
    # Creates a list with available interfaces. Caches results for "cache" secs
    def setCache
        puts "scanning available networks" if @options[:verbose]
        ifup
        @available = []
        # Code here could use a clean up
        Open3.popen3('iwlist', @interface, 'scan') { |i,o,e,t|
            o.gets # throw away first line
            while output = o.gets 
                if /Cell (?<n>\d.) - Address: (?<add>.*)/ =~ output
                    parsing = n.to_i - 1; # Cell starts at 01, array starts at 0
                    @available[parsing] = {}
                    @available[parsing]["addr"] = add
                end
                if /Quality=(?<sig>\d\d)\/70/ =~ output
                    @available[parsing]["sig"] = sig 
                end
                if /Encryption key:(?<enc>.*)/ =~ output
                    @available[parsing]["enc"] = enc 
                end
                if /ESSID:"(?<essid>.*)"/ =~ output
                    @available[parsing]["essid"] = essid 
                end
                if /IE: IEEE \d*\.\d\d.\/(?<enctype>.*) V/ =~ output
                    @available[parsing]["enctype"] = enctype 
                end
            end	
            puts "Error scanning interface #{@interface} for connections!" unless t.value == 0
        }
        @cacheTime = Time.now
    end
    # Returns the available networks.
    def getNetworks(plain=false)
        if Time.now - @cacheTime > @config["validcache"]
            setCache
        end
        return @available if plain
        ret = "Address\t\t\tSignal\tEncrypt\tESSID\n"
        @available.each{ |a|
            ret << "#{a["addr"]}\t#{(a["sig"].to_f/70.0*100.0).floor}%\t"
            if a["enc"] == "on"
                if a["enctype"] == "WPA2"
                    ret << "WPA2"
                else
                    ret << "other"
                end
            else
                ret << "open"
            end
            ret << "\t#{a["essid"]}\n"
        }
        return ret
    end
    def autoConnect
        # Reads priorities from auto.conf
        priority = []
        autoConfig = YAML.load_file(File.join(@config["varlib"], "auto.conf")) rescue autoConfig = {}
        autoConfig.sort_by {|key, value| -value}.each {|e| priority << e[0]}
        return "Unable to autoconnect: no networks are configured to autoconnect!" if priority.length == 0

        # Reads available networks
        nets = []
        getNetworks(true).each{|n| nets << n["essid"]} 

        # TODO: remove networks marked as FAILED
        nets = priority & nets # Intersection, ordered by priority

        return "Unable to autoconnect: no configured nets available!" if nets.length == 0
        return connect!(nets[0])
    end
    # adds this network to the autoconnect list
    def addToAC(essid, pr)
        autoConfig = YAML.load_file(File.join(@config["varlib"], "auto.conf")) rescue autoConfig = {}
        autoConfig[essid.to_str] = pr.to_i
        File.open(File.join(@config["varlib"], "auto.conf"), 'w') { |f| f.puts autoConfig.to_yaml }
        return "Configured to autoconnect to #{essid} with priority #{pr}"
    end
    def dropFromAC(essid)
        autoConfig = YAML.load_file(File.join(@config["varlib"], "auto.conf")) rescue autoConfig = {}
        autoConfig.delete(essid)
        File.open(File.join(@config["varlib"], "auto.conf"), 'w') { |f| f.puts autoConfig.to_yaml }
        return "Configured to avoid autoconnect to #{essid}"
    end
    def showStatus
        r = "wicmand version #{Version} status:\n\n"
        if @connected.nil?
            r << "Not connected\n\n"
        else
            r << "Connected to #{@connected}. "
            r << healthCheck << "\n"
        end
        r << showAC
        return r
    end
    def showAC
        autoConfig = YAML.load_file(File.join(@config["varlib"], "auto.conf")) rescue autoConfig = {}
        return "No networks configured for autoconnect" if autoConfig == {}
        ret = "The following networks will be attempted by autoconnect:\n"
        ret << "Priority\tESSID\n"
        autoConfig.sort_by{ |k, v| -v}.each{ |a|
            ret << "#{a[1]}\t\t#{a[0]}\n"
        }
        return ret
    end
end

# Starts the daemon with command-line options
Wicmand.new(options)
