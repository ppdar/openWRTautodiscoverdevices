Device Discovery for OpenWRT is a widget that appears at the bottom of the status page and will show a list of all the OpenWRT routers/APs on your local network.
 - Openwrt devices will auto discover themselves on the network and update their listing in the widget.
 - They will show their hostname and ip address in the listing.
 - Users can click on the hostname to go directly to that devices web page.
 - The utility itself is tiny and requires just 2 dependency modules which are themselves relatively small.
 - The utility is basically just 2 files: a single daemon file and its javascript webpage widget. The other files are the init.d starter script and the file access permissions file. 
 - Total flash space including the depencies will add a maximum of 80 KB on top of a base openWRT image (i.e. LuCi is pre-installed)
 - The footprint breakdown as follows:
 - 
   - luci-app-devicediscovery	~10 KB
   - luasocket (handles network communications)	~51 KB
   - libuci-lua (script interpreter) 	~7 KB

  

<img width="1238" height="284" alt="openwrt-device-discovery" src="https://github.com/user-attachments/assets/12e18b22-c07b-45e7-ad49-19a2e1e91e8c" />
