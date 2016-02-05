#!/usr/bin/env ruby
# This file contains the wicman client that is used to configure
# and connect to wireless networks.
#
# NOTE: If the wicmand daemon was started with a non-default
# configuration file, make sure wicman client runs with the
# same file!

require 'yaml'
require 'optparse'
require 'socket'

Version = "0.0.4"

# Parses command line arguments
options = {}
optparse = OptionParser.new do |opts|
    opts.banner = "wicman version #{Version}\nUsage:\nOnly one command may be specified at a time"

    opts.separator ""
    opts.separator "General options:"

    options[:verbose] = false
    opts.on( '-v', '--verbose', 'Output more information' ) do
        options[:verbose] = true
    end
    options[:configfile] = "/etc/wicmand.conf"
    opts.on( '-f', '--configfile FILE', 'Use alternate configuration file' ) { |file|
        options[:configfile] = file
    }
    opts.separator ""
    opts.separator "Commands:"
    opts.separator "(use \"\" if the network name contains spaces)"
    options[:command] = nil
    options[:essid] = nil
    options[:passphrase] = nil
    options[:pr] = 0
    opts.on( '-l', '--list', 'List available networks' ) do
        options[:command] = "list"
    end
    opts.on( '-g', '--configure ESSID', 
            'Configures wicman to use a passphrase to',
            'connect to this ESSID' ) do |essid|
                options[:command] = "conf"
                options[:essid] = essid
            end
            opts.on( '-c', '--connect [ESSID]', 
                    'Connects to a specified network. If no ESSID',
                    'is given, connects to the autoconnect list.' ) do |essid|
                        options[:command] = "conn"
                        options[:essid] = essid
                    end
                    opts.on( '-a', '--autoconnect ESSID', 
                            'wicman will autoconnect to this network',
                            'when available' ) do |essid|
                                options[:command] = "auto"
                                options[:essid] = essid
                            end
                            opts.on( '-s', '--show', 
                                    'Shows the network status and list of networks',
                                    'enabled for autoconnection.') do |essid|
                                        options[:command] = "show"
                                    end
                                    opts.on( '-x', '--dont-autoconnect ESSID', 
                                            'Drops ESSID from the list of auto-connections.') do |essid|
                                        options[:command] = "xauto"
                                        options[:essid] = essid
                                    end
                                    opts.on( '-d', '--disconnect', 'Disconnects from all networks' ) do 
                                        options[:command] = "disc"
                                    end
                                    opts.on( '-H', '--health', 'Forces a health check on the connection' ) do 
                                        options[:command] = "health"
                                    end
                                    opts.on( '-h', '--help', 'Display this screen' ) {
                                        puts opts
                                        exit
                                    }
                                    opts.separator ""
                                    opts.separator "Specific options:"
                                    opts.on( '-p', '--passphrase [pp]', 
                                            'With -g or -c, sets the passphrase',
                                            'If -p is specified but no passphrase is given, reads from stdin' ) do |pp|
                                                raise "-p should only be used after -g or -c" if options[:command] != "conf" and options[:command] != "conn"
                                                if pp.nil? then
                                                    puts "Enter passphrase for network #{options[:essid]}:"
                                                    system "stty -echo"
                                                    pp = gets.chomp()
                                                    system "stty echo"
                                                end
                                                options[:pp] = pp
                                            end
                                            opts.on( '-r', '--priority pr', 'With -a, sets the priority for this network',
                                                    'Higher priority nets are attempted first' ) do |pr|
                                                raise "-r should only be used with -a" if options[:command] != "auto"
                                                options[:pr] = pr
                                            end

                                            opts.separator ""
                                            opts.separator "Examples:"
                                            opts.separator "wicman -g \"my net\" -p mypphrase    # configures before first use"
                                            opts.separator "wicman -c \"my net\"                 # connects only this time"
                                            opts.separator "wicman -a \"my net\" -r 99           # autoconnect with a high priority"
                                            opts.separator ""
end

begin
    optparse.parse!
rescue
    puts "Error while parsing input:"
    puts $!
    exit
end

if options[:command].nil?
    puts "You must specify one command for wicman. Use wicman -h for details"
    exit
end

puts "Reading global configuration from #{options[:configfile]}" if options[:verbose]
begin
    config = YAML.load_file(options[:configfile])
rescue
    puts "Configuration file at #{options[:configfile]} not found or not readable."
    puts $!
    exit
end

sfile = File.join(config["temp"], "wicmand.socket")

status = ""

while status == "" do
    puts "Opening communication with wicmand daemon on #{sfile}" if options[:verbose]
    begin
        client = UNIXSocket.new sfile
    rescue
        puts "Unable to open communication with wicmand daemon.\nMake sure it is running and using the same configuration file as this program."
        puts $!
        exit
    end
    # Sends the message to the daemon
    begin
        client.write "#{options[:command]} \"#{options[:essid]}\" \"#{options[:pp]}\" #{options[:pr]}\n"
    rescue
        puts "Unable to communicate with wicmand daemon. Error was:"
        puts $!
        exit
    end

    # Gets the daemon response
    status = client.gets.chomp

    # Treats internal messages
    if status == "needpp"
        puts "Enter passphrase for network #{options[:essid]}:"
        system "stty -echo"
        options[:pp] = gets.chomp()
        system "stty echo"
        status = ""
    end
end

# if it reaches here, then the status is not an internal message, so we just dump everything to screen
puts status
loop {
    puts client.gets.chomp
} rescue nil
