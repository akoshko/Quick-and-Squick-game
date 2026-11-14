# Derived from https://github.com/kenyoni-software/godot-addons (qr_code v2.0.0, MIT)
extends RefCounted
## Minimal QR encoder: byte mode (UTF-8), error correction level M, versions 1..10,
## automatic version and mask selection.

const MAX_VERSION := 10

## Error correction level M per version 1..10:
## [data codewords, EC codewords per block, group 1 blocks, group 1 block size, group 2 blocks, group 2 block size]
const _EC_M: Array = [
	[16, 10, 1, 16, 0, 0],
	[28, 16, 1, 28, 0, 0],
	[44, 26, 1, 44, 0, 0],
	[64, 18, 2, 32, 0, 0],
	[86, 24, 2, 43, 0, 0],
	[108, 16, 4, 27, 0, 0],
	[124, 18, 4, 31, 0, 0],
	[154, 22, 2, 38, 2, 39],
	[182, 22, 3, 36, 2, 37],
	[216, 26, 4, 43, 1, 44],
]

const _ALIGNMENT_PATTERN_POSITIONS: Array = [
	[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50],
]

## remainder bits after structured data bits
const _REMAINDER_BITS: Array = [0, 7, 7, 7, 7, 7, 0, 0, 0, 0]

const _EC_LEVEL_M := 0  ## format-info bits for level M
const _DARK := 1
const _LIGHT := 0

static var _exp_table: PackedByteArray = []
static var _log_table: PackedByteArray = []


## Encodes text as UTF-8 bytes. Returns the module matrix row by row (1 = dark),
## dimension = sqrt(size). Returns an empty array if the text does not fit in version 10.
static func encode(text: String) -> PackedByteArray:
	var data := text.to_utf8_buffer()
	var version := _min_version(data.size())
	if version == -1:
		push_error("QR: %d bytes do not fit in version %d (level M, max %d bytes)" % [data.size(), MAX_VERSION, _capacity(MAX_VERSION)])
		return PackedByteArray()
	var codewords := _structure_data(version, _encode_data(version, data))
	return _mask_qr(version, _place_modules(version, codewords))


## Generates a QR code image with a quiet zone (in modules) around it.
static func generate_image(qr_data: PackedByteArray, module_size: int = 1, light_module_color: Color = Color.WHITE, dark_module_color: Color = Color.BLACK, quiet_zone_size: int = 4) -> Image:
	module_size = maxi(1, module_size)
	quiet_zone_size = maxi(0, quiet_zone_size)
	var dimension := int(sqrt(qr_data.size()))
	var image_size := (dimension + 2 * quiet_zone_size) * module_size
	var image := Image.create_empty(image_size, image_size, false, Image.FORMAT_RGB8)
	image.fill(light_module_color)
	for y: int in range(dimension):
		for x: int in range(dimension):
			if qr_data[x + y * dimension] == _DARK:
				image.fill_rect(Rect2i((x + quiet_zone_size) * module_size, (y + quiet_zone_size) * module_size, module_size, module_size), dark_module_color)
	return image


static func _calc_dimension(version: int) -> int:
	return 21 + 4 * (version - 1)


static func _char_count_bits(version: int) -> int:
	return 8 if version < 10 else 16


## maximum byte count for a version
static func _capacity(version: int) -> int:
	return (_EC_M[version - 1][0] * 8 - 4 - _char_count_bits(version)) / 8


static func _min_version(byte_count: int) -> int:
	for version: int in range(1, MAX_VERSION + 1):
		if byte_count <= _capacity(version):
			return version
	return -1


static func _append_bits(bits: PackedByteArray, value: int, count: int) -> void:
	for idx: int in range(count - 1, -1, -1):
		bits.append((value >> idx) & 1)


## data codewords: mode, count, bytes, terminator, padding
static func _encode_data(version: int, data: PackedByteArray) -> PackedByteArray:
	var bits := PackedByteArray()
	_append_bits(bits, 0b0100, 4)  # byte mode
	_append_bits(bits, data.size(), _char_count_bits(version))
	for val: int in data:
		_append_bits(bits, val, 8)
	var required_bytes: int = _EC_M[version - 1][0]
	_append_bits(bits, 0, mini(8 * required_bytes - bits.size(), 4))  # terminator
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var bytes := PackedByteArray()
	for idx: int in range(0, bits.size(), 8):
		var byte := 0
		for bit: int in range(8):
			byte = (byte << 1) | bits[idx + bit]
		bytes.append(byte)
	var pad := 0
	while bytes.size() < required_bytes:
		bytes.append(236 if pad % 2 == 0 else 17)
		pad += 1
	return bytes


## splits into blocks, adds Reed-Solomon codewords and interleaves; returns the final bit stream
static func _structure_data(version: int, data: PackedByteArray) -> PackedByteArray:
	var ec: Array = _EC_M[version - 1]
	var blocks: Array[PackedByteArray] = []
	var ec_blocks: Array[PackedByteArray] = []
	var offset := 0
	for group: int in range(2):
		for _block: int in range(ec[2 + group * 2]):
			var block := data.slice(offset, offset + ec[3 + group * 2])
			offset += block.size()
			blocks.append(block)
			ec_blocks.append(_rs_encode(block, ec[1]))
	var bits := PackedByteArray()
	for idx: int in range(maxi(ec[3], ec[5])):
		for block: PackedByteArray in blocks:
			if idx < block.size():
				_append_bits(bits, block[idx], 8)
	for idx: int in range(ec[1]):
		for block: PackedByteArray in ec_blocks:
			_append_bits(bits, block[idx], 8)
	_append_bits(bits, 0, _REMAINDER_BITS[version - 1])
	return bits


#### Reed-Solomon over GF(256), polynomial 0x11D

static func _init_tables() -> void:
	if not _exp_table.is_empty():
		return
	_exp_table.resize(256)
	_log_table.resize(256)
	var value := 1
	for exp: int in range(255):
		_exp_table[exp] = value
		_log_table[value] = exp
		value <<= 1
		if value & 256:
			value ^= 0x11D
	_exp_table[255] = _exp_table[0]


static func _gf_mul(lhs: int, rhs: int) -> int:
	if lhs == 0 or rhs == 0:
		return 0
	return _exp_table[(_log_table[lhs] + _log_table[rhs]) % 255]


static func _rs_encode(data: PackedByteArray, code_words: int) -> PackedByteArray:
	_init_tables()
	# generator polynomial (x - a^0)(x - a^1)...(x - a^(n-1)), highest degree first
	var gen := PackedByteArray([1])
	for exp: int in range(code_words):
		var next := PackedByteArray()
		next.resize(gen.size() + 1)
		next.fill(0)
		for idx: int in range(gen.size()):
			next[idx] ^= gen[idx]
			next[idx + 1] ^= _gf_mul(gen[idx], _exp_table[exp])
		gen = next
	var msg := data.duplicate()
	msg.resize(data.size() + code_words)
	for idx: int in range(data.size()):
		var coef: int = msg[idx]
		if coef != 0:
			for p_idx: int in range(1, gen.size()):
				msg[idx + p_idx] ^= _gf_mul(gen[p_idx], coef)
	return msg.slice(data.size())


#### Matrix layout

static func _get_alignment_pattern_positions(version: int) -> Array[Vector2i]:
	var dimension := _calc_dimension(version)
	var positions: Array[Vector2i] = []
	for row: int in _ALIGNMENT_PATTERN_POSITIONS[version - 1]:
		for col: int in _ALIGNMENT_PATTERN_POSITIONS[version - 1]:
			# do not overlap finder positions
			if (row - 2 < 8 and col - 2 < 8) or (row - 2 < 8 and col + 2 > dimension - 8) or (row + 2 >= dimension - 8 and col - 2 < 8):
				continue
			positions.append(Vector2i(row, col))
	return positions


## pos is upper left corner, 7 x 7
static func _place_finder(data: PackedByteArray, dimension: int, pos: Vector2i) -> void:
	for y: int in range(7):
		for x: int in range(7):
			var ring := maxi(absi(x - 3), absi(y - 3))
			data[(pos.x + x) + (pos.y + y) * dimension] = _LIGHT if ring == 2 else _DARK


## pos is center, 5 x 5
static func _place_align_pattern(data: PackedByteArray, dimension: int, pos: Vector2i) -> void:
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var ring := maxi(absi(x), absi(y))
			data[(pos.x + x) + (pos.y + y) * dimension] = _LIGHT if ring == 1 else _DARK


static func _is_data_module(dimension: int, alignment_pattern_pos: Array[Vector2i], pos: Vector2i) -> bool:
	# finder patterns with separators and format information area
	if (pos.x <= 8 and pos.y <= 8) or (pos.x >= dimension - 8 and pos.y <= 8) or (pos.x <= 8 and pos.y >= dimension - 8):
		return false
	# timing patterns
	if pos.x == 6 or pos.y == 6:
		return false
	# version information area (version >= 7)
	if dimension >= 45:
		if pos.x <= 5 and pos.y >= dimension - 11 and pos.y <= dimension - 9:
			return false
		if pos.y <= 5 and pos.x >= dimension - 11 and pos.x <= dimension - 9:
			return false
	for align_pos: Vector2i in alignment_pattern_pos:
		if absi(pos.x - align_pos.x) <= 2 and absi(pos.y - align_pos.y) <= 2:
			return false
	return true


## returns module data ordered by rows: index = x + y * dimension
static func _place_modules(version: int, bits: PackedByteArray) -> PackedByteArray:
	var dimension := _calc_dimension(version)
	var data := PackedByteArray()
	data.resize(dimension * dimension)
	data.fill(_LIGHT)  # separators and quiet areas stay light
	_place_finder(data, dimension, Vector2i(0, 0))
	_place_finder(data, dimension, Vector2i(0, dimension - 7))
	_place_finder(data, dimension, Vector2i(dimension - 7, 0))
	var alignment_pattern_pos := _get_alignment_pattern_positions(version)
	for pos: Vector2i in alignment_pattern_pos:
		_place_align_pattern(data, dimension, pos)
	for idx: int in range(8, dimension - 8):
		data[idx + 6 * dimension] = (idx + 1) % 2
		data[6 + idx * dimension] = (idx + 1) % 2
	data[8 + (dimension - 8) * dimension] = _DARK  # dark module

	# zig-zag data placement, two columns at a time from the bottom right
	var bit_idx := 0
	var base_col := dimension - 1
	var upwards := true
	while base_col > 0:
		if base_col == 6:
			base_col -= 1  # skip vertical timing pattern
		for step: int in range(dimension):
			var row := dimension - 1 - step if upwards else step
			for offset: int in range(2):
				var pos := Vector2i(base_col - offset, row)
				if _is_data_module(dimension, alignment_pattern_pos, pos):
					data[pos.x + pos.y * dimension] = bits[bit_idx]
					bit_idx += 1
		base_col -= 2
		upwards = not upwards
	assert(bit_idx == bits.size(), "failed to place all data (%d of %d)" % [bit_idx, bits.size()])
	return data


static func _mask_bit(mask_pattern: int, x: int, y: int) -> bool:
	match mask_pattern:
		0: return (x + y) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (x + y) % 3 == 0
		4: return (x / 3 + y / 2) % 2 == 0
		5: return (x * y % 2) + (x * y) % 3 == 0
		6: return ((x * y % 2) + (x * y) % 3) % 2 == 0
		_: return (((x + y) % 2) + (x * y) % 3) % 2 == 0


static func _place_format(data: PackedByteArray, dimension: int, mask_pattern: int) -> void:
	var base_code := (_EC_LEVEL_M << 3) | mask_pattern
	var code := base_code
	for _idx: int in range(10):
		code = (code << 1) ^ ((code >> 9) * 0x537)
	code = (base_code << 10 | code) ^ 0x5412
	for idx: int in range(8):
		var pos := idx + 1 if idx > 5 else idx  # skip timing pattern
		data[pos + 8 * dimension] = (code >> (14 - idx)) & 1  # upper left, horizontal
		data[8 + pos * dimension] = (code >> idx) & 1  # upper left, vertical
		data[(dimension - 1 - idx) + 8 * dimension] = (code >> idx) & 1  # upper right
	for idx: int in range(7):
		data[8 + (dimension - 1 - idx) * dimension] = (code >> (14 - idx)) & 1  # lower left


static func _place_version(data: PackedByteArray, version: int) -> void:
	if version < 7:
		return
	var code := version
	for _idx: int in range(12):
		code = (code << 1) ^ ((code >> 11) * 0x1F25)
	code = version << 12 | code
	var dimension := _calc_dimension(version)
	for idx: int in range(18):
		var x := idx / 3
		var y := dimension - 11 + idx % 3
		data[x + y * dimension] = (code >> idx) & 1
		data[y + x * dimension] = (code >> idx) & 1


## applies all 8 masks (with format/version info) and keeps the one with the lowest penalty
static func _mask_qr(version: int, data: PackedByteArray) -> PackedByteArray:
	var dimension := _calc_dimension(version)
	var alignment_pattern_pos := _get_alignment_pattern_positions(version)
	var best := PackedByteArray()
	var best_rating := 9223372036854775807
	for mask_pattern: int in range(8):
		var cur := data.duplicate()
		for y: int in range(dimension):
			for x: int in range(dimension):
				if _mask_bit(mask_pattern, x, y) and _is_data_module(dimension, alignment_pattern_pos, Vector2i(x, y)):
					cur[x + y * dimension] ^= 1
		_place_format(cur, dimension, mask_pattern)
		_place_version(cur, version)
		var rating := _calc_mask_rating(cur, dimension)
		if rating < best_rating:
			best_rating = rating
			best = cur
	return best


static func _calc_mask_rating(data: PackedByteArray, dimension: int) -> int:
	var rating := 0
	for line: int in range(dimension):
		# condition 1: runs of 5+ same-colour modules, horizontal and vertical
		for horizontal: bool in [true, false]:
			var count := 0
			var block_value := -1
			for idx: int in range(dimension):
				var cur: int = data[idx + line * dimension] if horizontal else data[line + idx * dimension]
				if cur == block_value:
					count += 1
				else:
					if count >= 5:
						rating += count - 2
					count = 1
					block_value = cur
			if count >= 5:
				rating += count - 2
	# condition 2: 2x2 blocks of one colour
	for y: int in range(dimension - 1):
		for x: int in range(dimension - 1):
			var val: int = data[x + y * dimension] + data[x + 1 + y * dimension] + data[x + (y + 1) * dimension] + data[x + 1 + (y + 1) * dimension]
			if val == 0 or val == 4:
				rating += 3
	# condition 3: finder-like 1:1:3:1:1 pattern with 4 light modules on either side
	for line: int in range(dimension):
		for start: int in range(dimension - 6):
			for horizontal: bool in [true, false]:
				var step := 1 if horizontal else dimension
				var base := (start + line * dimension) if horizontal else (line + start * dimension)
				if not (data[base] and not data[base + step] and data[base + 2 * step] and data[base + 3 * step] \
						and data[base + 4 * step] and not data[base + 5 * step] and data[base + 6 * step]):
					continue
				if start >= 4 and not (data[base - step] or data[base - 2 * step] or data[base - 3 * step] or data[base - 4 * step]):
					rating += 40
				if start <= dimension - 11 and not (data[base + 7 * step] or data[base + 8 * step] or data[base + 9 * step] or data[base + 10 * step]):
					rating += 40
	# condition 4: dark/light balance
	var percent := int(data.count(_DARK) / float(dimension * dimension) * 100 - 50)
	rating += absi(percent) / 5 * 10
	return rating
