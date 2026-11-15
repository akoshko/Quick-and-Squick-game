class_name PlayerRegistry
extends RefCounted
## Token -> player slot registry with reconnect hold. Time is supplied by the caller (seconds).

const HOLD_SECONDS := 60.0
## Длина ника после проверки (самый длинный ник из слов CharacterLook — 23 символа).
const NAME_MAX := 24

var _by_player: Dictionary = {}  # player_id -> record Dictionary
var _by_token: Dictionary = {}   # token -> player_id
var _banned: Dictionary = {}     # token -> {player_id, number, name, at}
var _next_number := 1


## profile — профиль из hello (формат PlayerProfile.to_dict()); проверяется clean_profile.
## Пустой профиль у вернувшегося игрока (тот же токен) оставляет прежний.
func admit(token: String, role: String, now: float, profile: Variant = {}) -> Dictionary:
	var res := {"ok": false, "player_id": "", "number": 0, "reason": "", "replaced_peer": 0}
	if not _valid_token(token):
		res.reason = "bad_hello"
		return res
	if role == "screen":
		res.ok = true
		return res
	if role != "player":
		res.reason = "bad_hello"
		return res
	if _banned.has(token):
		res.reason = "kicked"
		return res
	if _by_token.has(token):
		var rec: Dictionary = _by_player[_by_token[token]]
		if rec.state == "connected":
			res.replaced_peer = rec.peer_id
		rec.state = "connected"
		rec.held_since = 0.0
		rec.reconnects += 1
		if profile is Dictionary and not (profile as Dictionary).is_empty():
			rec.profile = clean_profile(profile, rec.number)
		res.ok = true
		res.player_id = rec.player_id
		res.number = rec.number
		return res
	var n := _next_number
	_next_number += 1
	var pid := "p%d" % n
	_by_player[pid] = {
		"player_id": pid, "number": n, "state": "connected", "joined_at": now,
		"reconnects": 0, "peer_id": 0, "token": token, "held_since": 0.0,
		"profile": clean_profile(profile, n),
	}
	_by_token[token] = pid
	res.ok = true
	res.player_id = pid
	res.number = n
	return res


func bind_peer(player_id: String, peer_id: int) -> void:
	if _by_player.has(player_id):
		_by_player[player_id].peer_id = peer_id


func peer_lost(peer_id: int, now: float) -> String:
	if peer_id == 0:
		return ""
	for rec: Dictionary in _by_player.values():
		if rec.peer_id == peer_id and rec.state == "connected":
			rec.state = "held"
			rec.held_since = now
			return rec.player_id
	return ""


func expire(now: float) -> PackedStringArray:
	var gone := PackedStringArray()
	for pid: String in _by_player.keys():
		var rec: Dictionary = _by_player[pid]
		if rec.state == "held" and now - rec.held_since >= HOLD_SECONDS:
			gone.append(pid)
	for pid in gone:
		_by_token.erase(_by_player[pid].token)
		_by_player.erase(pid)
	return gone


func ban(player_id: String, now := 0.0, name := "") -> int:
	if not _by_player.has(player_id):
		return 0
	var rec: Dictionary = _by_player[player_id]
	_banned[rec.token] = {
		"player_id": player_id, "number": rec.number,
		"name": name if name != "" else str(rec.profile.name), "at": now,
	}
	var peer: int = rec.peer_id if rec.state == "connected" else 0
	_by_token.erase(rec.token)
	_by_player.erase(player_id)
	return peer


## Снимает бан; false, если такого выгнанного нет. Тот же токен снова проходит admit как новый игрок.
func unban(player_id: String) -> bool:
	for tok: String in _banned.keys():
		if _banned[tok].player_id == player_id:
			_banned.erase(tok)
			return true
	return false


## Выгнанные: {player_id, number, name, at} (at: секунды часов вызывающего на момент бана).
func banned() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in _banned.values():
		out.append(b.duplicate())
	return out


func player_for_peer(peer_id: int) -> String:
	if peer_id == 0:
		return ""
	for rec: Dictionary in _by_player.values():
		if rec.peer_id == peer_id and rec.state == "connected":
			return rec.player_id
	return ""


func peer_for_player(player_id: String) -> int:
	if _by_player.has(player_id) and _by_player[player_id].state == "connected":
		return _by_player[player_id].peer_id
	return 0


func records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _by_player.values():
		out.append({
			"player_id": rec.player_id, "number": rec.number, "state": rec.state,
			"joined_at": rec.joined_at, "reconnects": rec.reconnects, "peer_id": rec.peer_id,
			"name": rec.profile.name, "skin": skin_id(rec.profile), "profile": rec.profile.duplicate(),
		})
	return out


## Профиль игрока (результат clean_profile) или {} для неизвестного игрока.
func profile_of(player_id: String) -> Dictionary:
	return _by_player[player_id].profile.duplicate() if _by_player.has(player_id) else {}


## Проверенный профиль — единственный источник имени и скина игрока на сервере:
## {name, hoodie, hair_style, hair_color}. Ник — два слова из CharacterLook (как в создании
## персонажа, своё не вписать); пробелы по краям срезаются, длина не больше NAME_MAX; без
## допустимых слов — «Игрок N». Внешность — только известные id, иначе вариант по умолчанию.
static func clean_profile(data: Variant, number: int) -> Dictionary:
	var d: Dictionary = data if data is Dictionary else {}
	var first := str(d.get("title_first", "")).strip_edges()
	var second := str(d.get("title_second", "")).strip_edges()
	var name := ""
	if first in CharacterLook.TITLE_FIRST and second in CharacterLook.TITLE_SECOND:
		name = CharacterLook.make_nickname(first, second).strip_edges().left(NAME_MAX).strip_edges()
	if name == "":
		name = "Игрок %d" % number
	return {
		"name": name,
		"hoodie": CharacterLook.find(CharacterLook.HOODIES, str(d.get("hoodie", ""))).id,
		"hair_style": CharacterLook.find(CharacterLook.HAIR_STYLES, str(d.get("hair_style", ""))).id,
		"hair_color": CharacterLook.find(CharacterLook.HAIR_COLORS, str(d.get("hair_color", ""))).id,
	}


## Идентификатор скина для админки: «худи/причёска/цвет волос».
static func skin_id(profile: Dictionary) -> String:
	if profile.is_empty():
		return ""
	return "%s/%s/%s" % [profile.get("hoodie", ""), profile.get("hair_style", ""), profile.get("hair_color", "")]


static func _valid_token(t: String) -> bool:
	if t.length() < 16 or t.length() > 128:
		return false
	for i in t.length():
		var c := t.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45
		if not ok:
			return false
	return true
