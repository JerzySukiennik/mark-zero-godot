extends SceneTree
## Can this machine bind the beacon port at all, and does anything arrive on it?
## Autoload-free on purpose, so it runs under --script:
##   godot --headless --path . --script res://tools/probe_udp.gd
func _init() -> void:
	for addr in ["*", "0.0.0.0"]:
		var u := PacketPeerUDP.new()
		var err := u.bind(27016, addr)
		print("bind 27016 on '%s' -> err %d (%s)" % [addr, err, error_string(err)])
		if err == OK:
			print("  bound. listening 6 s…")
			var t := Time.get_ticks_msec()
			var got := 0
			while Time.get_ticks_msec() - t < 6000:
				while u.get_available_packet_count() > 0:
					got += 1
					print("  packet from ", u.get_packet_ip(), ": ",
						u.get_packet().get_string_from_utf8().substr(0, 90))
				OS.delay_msec(50)
			print("  packets: ", got)
			u.close()
			return
	quit(0)
