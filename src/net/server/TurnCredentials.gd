class_name TurnCredentials
extends RefCounted
## coturn use-auth-secret (TURN REST) credentials.


## An empty secret is a configuration error: returns {} (no TURN) instead of HMAC with an empty key.
static func make(secret: String, user: String, now_unix: int, ttl := 86400) -> Dictionary:
	if secret.is_empty():
		push_error("NET: TURN_SECRET is empty, no TURN credentials")
		return {}
	var username := "%d:%s" % [now_unix + ttl, user]
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA1, secret.to_utf8_buffer())
	h.update(username.to_utf8_buffer())
	return {"username": username, "credential": Marshalls.raw_to_base64(h.finish())}


static func ice_servers(host: String, creds: Dictionary) -> Array:
	if host.is_empty() or creds.is_empty():
		return []
	return [{
		"urls": [
			"stun:%s:3478" % host,
			"turn:%s:3478?transport=udp" % host,
			"turn:%s:3478?transport=tcp" % host,
			"turns:%s:5349?transport=tcp" % host,
		],
		"username": creds.get("username", ""),
		"credential": creds.get("credential", ""),
	}]
