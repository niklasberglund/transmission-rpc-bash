# transmission-rpc-bash
Bash script for adding torrents for download to Transmission through Transmission's RPC protocol. Designed to be as portable as possible since one might want to run it on a NAS etc.

It can be used for adding torrents for download and tracking progress.

**Is the script not working as expected on your system? Please create an issue.**

# Usage
A very basic example is: `./transmission-rpc.sh -s myserver.com -u myusername -p mypassword <torrent>` where *\<torrent\>* can be an external link, local path or a magnet link.

For more usage information refer to the help text:
```
$ ./transmission-rpc.sh -h
    Usage: ./transmission-rpc.sh [options] <Torrent address or local file path>

    This script adds a torrent for download through Transmission's RPC protocol.
    
    EXAMPLE:
        ./transmission-rpc.sh -s my-server.com:9092 -u myUsername -p myPassword "http://www.frostclick.com/torrents/video/animation/Big_Buck_Bunny_1080p_surround_frostclick.com_frostwire.com.torrent"
        
    OPTIONS:
       -h      Show this help message
       -s      Server hostname and optionally port in the format host:port. Defaults to 127.0.0.1:9092 if not specified.
       -u      Server username
       -p      Server password
       -l      List active torrents and their progress
       -P      Used together with the -l flag. Makes -l list not only active torrents but also paused ones.
       -q      Quiet mode. Add torrent for download then exit - don't display download progress
       -c      Colored output
```
