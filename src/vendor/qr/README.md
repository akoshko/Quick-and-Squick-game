QR code encoder derived from kenyoni-software/godot-addons `qr_code` v2.0.0 (MIT, see LICENSE.md).
Slimmed down to what the projector QR needs, merged into a single qr_code.gd: byte mode (UTF-8),
error correction level M, automatic version selection (versions 1-10, up to 213 bytes),
Reed-Solomon, matrix layout, mask selection by penalty and image generation.
Removed: shift_jis.gd and Kanji mode, numeric/alphanumeric modes, ECI, other error correction
levels, versions 11-40, manual version/mask selection, the instance API, bit_stream.gd and
reed_solomon.gd (inlined), debug helpers.
