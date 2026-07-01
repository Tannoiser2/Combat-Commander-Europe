## Arte dei marcatori del gioco (pedine VASSAL): fortificazioni, fumo, incendio,
## buche. Mappa lo stato dell'esagono alle immagini reali in res://assets/markers/.
## Le texture sono in cache (load() le riusa). Le Mine non hanno un'immagine
## dedicata: il chiamante ripiega su un marcatore disegnato.
class_name MarkerArt
extends RefCounted

const DIR := "res://assets/markers/"

static var _cache: Dictionary = {}


static func _tex(file: String) -> Texture2D:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[file] = t
	return t


## Texture della fortificazione (Trincea/Casamatta/Bunker/Filo). null per Mine
## (nessuna immagine) o NONE.
static func fort_texture(fort: int) -> Texture2D:
	match fort:
		Domain.Fort.TRENCH:
			return _tex("Trench.png")
		Domain.Fort.PILLBOX:
			return _tex("Pillbox.png")
		Domain.Fort.BUNKER:
			return _tex("Bunker.png")
		Domain.Fort.WIRE:
			return _tex("Wire.png")
		_:
			return null


static func smoke_texture() -> Texture2D:
	return _tex("Smoke.png")


static func blaze_texture() -> Texture2D:
	return _tex("Blaze.png")


static func foxhole_texture() -> Texture2D:
	return _tex("Foxholes.png")
