#!/usr/bin/lua
-- Location /usr/sbin

-- Define application metadata
local VERSION = "0.3.3"

-- User requested version from command line
local arguments = arg or {}
if arguments[1] == "--version" then
    print("device discovery version " .. VERSION)
    os.exit(0)
end

-- Checking for luasocket dependency
local socket_ok, socket = pcall(require, "socket")
if not socket_ok then
    io.stderr:write("Error: Missing dependency 'luasocket'. Please install luasocket first.\n")
    os.exit(1)
end

-- Check for libuci-lua dependency
local uci_ok, uci = pcall(require, "uci")
if not uci_ok then
    io.stderr:write("Error: Missing dependency 'libuci-lua'. Please install libuci-lua first.\n")
    os.exit(1)
end

local socket = require("socket")
local uci = require("uci")

-- UDP Multicast Configuration
local group = "239.192.1.1"
local port = 50005
-- increasing timeout will cut CPU usage but may miss some broadcast packets
local SELECT_TIMEOUT = 0.05
-- transmit_interval assuming 20 access points on LAN the packet Count will be: 20 APs × 1 packet / transmit_interval 60 seconds = 0.33 packets/sec
-- UDP payload string = ip_address,hostname,TTL  total aroud 25~35 bytes + packet headers = 60 bytes total
-- 20 routers × 60 bytes = 1,200 bytes/min across entire LAN.
local TRANSMIT_INTERVAL = 60
local STATE_FILE = "/tmp/mcast_live.txt"
local SOCKET_TIMEOUT = 2.0 -- when network interface hangs silently set timeout

-- In-memory cache to store unique peers: [ip] = { hostname = name, last_seen = timestamp }
local active_peers = {}
local listen_udp = nil

---------------------------------------------------------
-- OBTAIN INTERFACE DATA
---------------------------------------------------------

-- Helper function to convert little-endian hex string to dot-decimal IP
local function hex_to_ip(hex)
    if #hex ~= 8 then return nil end
    local bytes = {}
    for i = 4, 1, -1 do
        local sub = hex:sub(i*2-1, i*2)
        table.insert(bytes, tonumber(sub, 16))
    end
    return table.concat(bytes, ".")
end

-- Finds the IP address listening on the target port (hex format)
local function get_listening_ip(target_port_hex)
    local f = io.open("/proc/net/tcp", "r")
    if not f then return nil end
    
    -- Skip header
    f:read("*line")
    
    for line in f:lines() do
        -- Match the local_address column (e.g., " 0100007F:0050 ")
        local local_addr = line:match("%s+%d+:%s+([%p%w]+)%s+")
        if local_addr then
            local ip_hex, port_hex = local_addr:match("([0-9A-F]+):([0-9A-F]+)")
            if port_hex == target_port_hex then
                f:close()
                return hex_to_ip(ip_hex)
            end
        end
    end
    f:close()
    return nil
end

-- Finds the primary interface
local function get_primary_interface()
    local f = io.open("/proc/net/route", "r")
    if not f then return "eth0" end -- fallback default
    
    f:read("*line") -- Skip header
    for line in f:lines() do
        -- Extract interface name and destination
        local iface, dest = line:match("^([%w%.%-]+)%s+([0-9A-F]+)")
        -- Skip loopback then find main routing path (usually dest 00000000)
        if iface and iface ~= "lo" then
            f:close()
            return iface
        end
    end
    f:close()
    return "eth0"
end

---------------------------------------------------------
-- SOCKET INITIALIZATION
---------------------------------------------------------

-- Dedicated helper function implementing timeout-recreate to guard against network stalls
local function create_multicast_socket(ip, port)
    if listen_udp then pcall(function() listen_udp:close() end) end
    local sock = socket.udp()
    if not sock then return nil end
    sock:setoption("reuseaddr", true)
    local success = sock:setsockname("*", port)
    if not success then sock:close() return nil end
    success = sock:setoption("ip-add-membership", { multiaddr = ip, interface = "0.0.0.0" })
    if not success then sock:close() return nil end
    sock:settimeout(SOCKET_TIMEOUT)
    return sock
end

-- Initial attempt to subscribe to the multicast group
listen_udp = create_multicast_socket(group, port)

-- Send hello to system logger on startup
os.execute("logger \"-t\" devicediscovery 'Service started successfully (Version " .. VERSION .. ")'")
print("Unified Device Discovery Daemon successfully initialized...")
print("Listening on " .. group .. ":" .. port .. " and sends announcements every " .. TRANSMIT_INTERVAL .. "s")
print("---------------------------------------------------------")

local last_transmit_time = 0

-- Helper function to write unique state to STATE_FILE
local function flush_peers_to_disk()
    local f = io.open(STATE_FILE, "w") -- "w" mode overwrites and truncates the file clean
    if f then
        for ip, info in pairs(active_peers) do
            f:write(string.format("%s,%s,%d\n", ip, info.hostname, info.last_seen))
        end
        f:close()
    end
end

socket.select(nil, nil, 10.0)

while true do
    local current_time = os.time()
    local state_changed = false

    ---------------------------------------------------------
    -- TASK 1: PROCESS INCOMING MULTICAST NETWORK PACKETS
    ---------------------------------------------------------
    if not listen_udp then
        listen_udp = create_multicast_socket(group, port)
    end

    if listen_udp then
        local data, ip_or_err, port_or_code = listen_udp:receivefrom()
        if data then
            -- debugger
            print(string.format("Received from %s:%d -> %s", ip_or_err, port_or_code, data))
            local ip_address, hostname, ttl = data:match("([^,]+),([^,]+),([^,]+)")
            if ip_address and hostname and ttl then
                -- debugger
                print(string.format('"%s":"%s":"%s"', hostname, ip_address, ttl))
                -- Insert or overwrite the tracking metrics for this unique IP
                active_peers[ip_address] = { hostname = hostname, last_seen = current_time }
                state_changed = true
            end
            -- debugger
            print("---------------------------------------------------------")
        else
            local err = ip_or_err
            if err == "timeout" then
                listen_udp = create_multicast_socket(group, port)
            else
                if listen_udp then listen_udp:close() end
                listen_udp = nil
            end
        end
    end

    ---------------------------------------------------------
    -- TASK 2: PRUNE EXPIRED HOSTS FROM IN-MEMORY CACHE
    ---------------------------------------------------------
    for ip, info in pairs(active_peers) do
        if current_time - info.last_seen >= 90 then
            active_peers[ip] = nil
            state_changed = true
        end
    end

    if state_changed then
        flush_peers_to_disk()
    end

    ---------------------------------------------------------
    -- TASK 3: INTERVAL-BASED NETWORK BEACON TRANSMISSION
    ---------------------------------------------------------
    if current_time - last_transmit_time >= TRANSMIT_INTERVAL then
        local cursor = uci.cursor()
        local hostname = "OpenWrt"
        cursor:foreach("system", "system", function(s)
            if s.hostname then
                hostname = s.hostname
                return false
            end
        end)
        cursor:close()

        local ip_address = "127.0.0.1"

        -- Evaluate via incorporated parsing methods
        local target_port = "0050" -- Hex for port 80
        local ip = get_listening_ip(target_port)

        if ip then
            if ip == "0.0.0.0" or ip == "127.0.0.1" then
                -- Find primary interface name
                local interface = get_primary_interface()
                
                -- Universal syntax compatible across OpenWrt 24 and 25
                local ip_cmd = string.format("ip -o -4 addr show dev %s", interface)
                local ip_pipe = io.popen(ip_cmd)
                if ip_pipe then
                    for ip_line in ip_pipe:lines() do
                        -- Pure Lua filtering for global scope and primary address lines
                        if ip_line:match("scope%s+global") and (ip_line:match("%s+primary%s+") or not ip_line:match("%s+secondary%s+")) then
                            local matched_ip = ip_line:match("inet%s+([%d%.]+)/")
                            if matched_ip then
                                ip_address = matched_ip
                                break
                            end
                        end
                    end
                    ip_pipe:close()
                end
            else
                -- Bound to a specific active non-loopback IP directly
                ip_address = ip
            end
        end

        local send_udp = socket.udp()
        if send_udp then
            send_udp:setoption("reuseaddr", true)
            if send_udp:setsockname("0.0.0.0", 0) and send_udp:setoption("ip-multicast-ttl", 32) then
                local payload = string.format("%s,%s,60", ip_address, hostname)
                send_udp:sendto(payload, group, port)
            end
            send_udp:close()
        end
        last_transmit_time = current_time
    end

    -- let CPU take a breath before sending and polling again
    socket.select(nil, nil, SELECT_TIMEOUT)
end
