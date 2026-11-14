class_name Msg
extends RefCounted
## Signaling protocol: JSON text messages with a string "t" field.

const HELLO := "hello"
const WELCOME := "welcome"
const REJECTED := "rejected"
const OFFER := "offer"
const ANSWER := "answer"
const CANDIDATE := "candidate"
const PING := "ping"
const PONG := "pong"
const WORLD_RESTART := "world_restart"


static func encode(type: String, data := {}) -> String:
	var d: Dictionary = data.duplicate()
	d["t"] = type
	return JSON.stringify(d)


static func decode(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	var v: Variant = j.data
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	if typeof(d.get("t")) != TYPE_STRING:
		return {}
	return d
