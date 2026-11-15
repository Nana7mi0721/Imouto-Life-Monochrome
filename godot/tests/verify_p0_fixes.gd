extends SceneTree

func _init() -> void:
	print("=== Running verify_p0_fixes.gd ===")
	var wolf := WolfGame.new()
	var root := "E:/Study/github program/Imouto Life/work/Data"
	if not wolf.open(root):
		push_error("open failed")
		quit(1)
		return

	wolf.start_title()
	for f in range(120):
		var p: Dictionary = wolf.frame()
		if not p.get("choices", []).is_empty():
			break
	wolf.reply(0)

	var found_ap_under_black := false
	var scenery_found := false

	for f in range(500):
		if f % 15 == 0:
			wolf.set_input(1, PackedInt32Array([1]), Vector2i.ZERO, 0)
		else:
			wolf.set_input(0, PackedInt32Array(), Vector2i.ZERO, 0)

		var p: Dictionary = wolf.frame()
		if not p.get("choices", []).is_empty():
			wolf.reply(0)

		var ap: Dictionary = p.get("ap", {})
		var sprites: Array = p.get("sprites", [])
		var texts: Array = p.get("texts", [])

		var has_black_cover := false
		for s in sprites:
			if s.get("number", 0) == 9000 and s.get("alpha", 0.0) > 0.0:
				has_black_cover = true
				break

		# Check Issue 1: If black cover is active, ap MUST NOT be exposed!
		if has_black_cover and not ap.is_empty():
			print("FAIL: Frame %d has black cover 9000, but ap is NOT empty: %s" % [f, str(ap)])
			found_ap_under_black = true

		# Check Issue 2: Scenery (-20000)
		for s in sprites:
			if s.get("number", 0) == -20000:
				if not scenery_found:
					print("PASS: Frame %d scenery found! number=-20000, rect=%s" % [f, str(s.get("rect"))])
					scenery_found = true
				break

		if f == 385 or f == 399:
			print("Frame %d: sprites_count=%d, texts_count=%d, ap=%s, has_black_cover=%s" % [
				f, sprites.size(), texts.size(), str(ap), str(has_black_cover)
			])

	if not found_ap_under_black:
		print("PASS: Prologue black screen has NO leaked action bar!")
	else:
		push_error("FAIL: Leaked action bar found under black screen")

	if scenery_found:
		print("PASS: Scenery background is present in SampleMapA!")
	else:
		push_error("FAIL: Scenery background NOT found")

	quit(0)
