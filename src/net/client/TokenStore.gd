class_name TokenStore
extends RefCounted
## Player token: 32 hex chars, kept in localStorage["qs_token"] on Web; if storage is unavailable
## the token lives for the lifetime of the tab.

const KEY := "qs_token"

static var _cached := ""


static func load_or_create() -> String:
	if _cached != "":
		return _cached
	var t := ""
	if OS.has_feature("web"):
		t = str(JavaScriptBridge.eval(
			"(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})()" % KEY))
	if not _is_valid(t):
		t = Crypto.new().generate_random_bytes(16).hex_encode()
		if OS.has_feature("web"):
			JavaScriptBridge.eval(
				"(function(){try{localStorage.setItem('%s','%s');}catch(e){}})()" % [KEY, t])
	_cached = t
	return t


static func _is_valid(t: String) -> bool:
	return t.length() == 32 and t.is_valid_hex_number()
