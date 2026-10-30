'use strict';
'require baseclass';
'require fs';
'require ui';

return baseclass.extend({
	title: _('Auto Discovered Devices'),

	// Native synchronous payload loading framework
	load: function() {
		// Discovered devices that are still alive are stored in /tmp/mcast_live.txt
		return fs.read('/tmp/mcast_live.txt').catch(function() { return ''; });
	},

	// Seamless native element assembly - zero manual DOM timers or hooks required
	render: function(file_content) {
		var current_time = Math.floor(Date.now() / 1000);
		var parsed_peers = {};

		// Safely extract the router IP/hostname you are currently logged into
		var local_router_ip = window.location.hostname || '';

		// Parse data from mcast_live.txt
		if (file_content && typeof file_content === 'string') {
			var lines = file_content.trim().split('\n');
			for (var i = 0; i < lines.length; i++) {
				var line = lines[i].trim();
				if (!line) continue;

				var parts = line.split(',');
				if (parts.length === 3) {
					var ip = parts[0].trim();
					var hostname = parts[1].trim();
					var packet_timestamp = parseInt(parts[2].trim(), 10);

					// Validate age alignment against the 10-minute (600s) buffer
					if (!isNaN(packet_timestamp) && (current_time - packet_timestamp) < 600) {
						parsed_peers[ip] = {
							hostname: hostname,
							last_seen: packet_timestamp
						};
					}
				}
			}
		}

		// Assemble presentation data
		var table_rows = [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Hostname')),
				E('th', { 'class': 'th' }, _('IP Address'))
			])
		];

		var peer_ips = Object.keys(parsed_peers).sort();

		if (peer_ips.length === 0) {
			table_rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'colspan': 2, 'style': 'text-align:center; font-style:italic;' }, _('No devices discovered yet. Check service is running'))
			]));
		} else {
			peer_ips.forEach(function(ip) {
				var device_name = parsed_peers[ip].hostname || '?';
				var hostname_link = E('a', { 'href': 'http://' + ip, 'target': '_blank', 'style': 'font-weight: bold;' }, device_name);

				// Format the IP label line and append an asterisk if it matches the current active system
				var ip_display = ip;
				if (ip === local_router_ip) {
					ip_display = ip + ' *';
				}

				table_rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, hostname_link),
					E('td', { 'class': 'td' }, ip_display)
				]));
			});
		}

		// Return the parent container directly into LuCI's internal layout execution queue
		return E('div', { 'class': 'cbi-section' }, [
			E('div', { 'class': 'cbi-section-node' }, [
				E('table', { 'class': 'table', 'id': 'mcast_live_table' }, table_rows)
			])
		]);
	}
});
