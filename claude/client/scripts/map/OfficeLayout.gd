class_name OfficeLayout
extends RefCounted
## Plano de la oficina de NexusCore (piso 14), en píxeles del mundo 2D del juego.
## Es la única fuente del plano: OfficeMap crea con él las colisiones 2D (lo que
## valida el movimiento), Office3D construye con él la oficina en 3D y la línea de
## vista usa sus muros, así que lo que se ve, lo que tapa y lo que choca nunca se
## separan.
##
## Las pistas traen su posición en el caso (campo "position" de cada pista); las de
## este plano caen dentro de su sala y con sitio libre alrededor. Los jugadores
## aparecen en (0, 0): el vestíbulo de la recepción.
##
## Muros "bajos" (corte tipo maqueta) para que la cámara vea dentro de cada sala.

const BOUNDS := Rect2(-640, -400, 4680, 1720)
const WALL := 20.0

## Salas: nombre, rectángulo, suelo y color de su luz. label = false: sin letrero.
## energy: intensidad de sus focos (1,25 por defecto); outdoor = true: al aire libre
## (sin focos de techo; Office3D la ilumina como exterior de noche).
static func rooms() -> Array:
	return [
		{"name": "SALA DE SEGURIDAD", "rect": Rect2(-640, -400, 480, 520), "floor": "rubber", "light": "#8FD3FF"},
		{"name": "RECEPCIÓN", "rect": Rect2(-640, 120, 800, 1200), "floor": "marble", "light": "#FFD9A8"},
		{"name": "RECEPCIÓN", "rect": Rect2(-160, -400, 320, 520), "floor": "marble", "light": "#FFD9A8", "label": false},
		{"name": "SALA DE SERVIDORES", "rect": Rect2(160, -400, 600, 760), "floor": "raised", "light": "#6CC8FF", "shadows": true},
		{"name": "DESPACHO DEL CEO", "rect": Rect2(760, -400, 640, 760), "floor": "wood", "light": "#FFC98A", "shadows": true},
		{"name": "OPEN SPACE", "rect": Rect2(1400, -400, 720, 760), "floor": "carpet", "light": "#D6E4FF", "shadows": true},
		{"name": "LABORATORIO DE IA", "rect": Rect2(2120, -400, 520, 760), "floor": "epoxy", "light": "#B69CFF"},
		{"name": "DEPARTAMENTO LEGAL", "rect": Rect2(2640, -400, 520, 760), "floor": "wood_dark", "light": "#FFD8A0", "shadows": true, "energy": 2.6},
		{"name": "RECURSOS HUMANOS", "rect": Rect2(3160, -400, 440, 760), "floor": "carpet_warm", "light": "#FFE9CF"},
		{"name": "CUARTO ELÉCTRICO", "rect": Rect2(3600, -400, 440, 760), "floor": "rubber", "light": "#FF8A2E", "energy": 5.0},
		{"name": "PASILLO", "rect": Rect2(160, 360, 3880, 200), "floor": "concrete", "light": "#BFD3FF", "label": false},
		{"name": "SALA DE JUNTAS", "rect": Rect2(160, 560, 600, 760), "floor": "wood_dark", "light": "#FFE2B8"},
		{"name": "CAFETERÍA", "rect": Rect2(760, 560, 640, 760), "floor": "terrazzo", "light": "#FFC27A", "shadows": true},
		{"name": "ARCHIVO Y RECICLAJE", "rect": Rect2(1400, 560, 560, 760), "floor": "vinyl", "light": "#E2F7EA"},
		{"name": "FINANZAS", "rect": Rect2(1960, 560, 680, 760), "floor": "carpet_warm", "light": "#FFE7C2"},
		{"name": "GIMNASIO", "rect": Rect2(2640, 560, 640, 760), "floor": "rubber", "light": "#CFE8FF", "energy": 5.0},
		{"name": "TERRAZA", "rect": Rect2(3280, 560, 760, 760), "floor": "deck", "light": "#9DB3FF", "outdoor": true},
	]

static func _w(ax: float, ay: float, bx: float, by: float, kind: String, h := 0.7) -> Dictionary:
	return {"a": Vector2(ax, ay), "b": Vector2(bx, by), "kind": kind, "h": h}

## Muros: tramo de a → b, tipo y alto (m). Tipos: back (fachada con ventanales),
## side (laterales exteriores), front (antepecho delantero), solid, glass, planter,
## railing (barandilla de cristal de la terraza).
## Las puertas son los huecos entre tramos.
static func walls() -> Array:
	var w := []
	# Exterior.
	w.append(_w(-650, -400, 4050, -400, "back", 3.0))
	w.append(_w(-640, -400, -640, 1320, "side", 2.2))
	w.append(_w(4040, -400, 4040, 560, "side", 2.2))
	w.append(_w(-650, 1320, 3280, 1320, "front", 0.35))
	# Terraza: barandilla de cristal al sur y al este (vistas a la ciudad).
	w.append(_w(3280, 1320, 4050, 1320, "railing", 1.05))
	w.append(_w(4040, 560, 4040, 1320, "railing", 1.05))
	# Sala de seguridad (puerta a la recepción entre x = -460 y -340).
	w.append(_w(-160, -400, -160, 120, "solid"))
	w.append(_w(-640, 120, -460, 120, "solid"))
	w.append(_w(-340, 120, -160, 120, "solid"))
	# Recepción | salas (el pasillo queda abierto).
	w.append(_w(160, -400, 160, 360, "solid"))
	w.append(_w(160, 560, 160, 1320, "glass"))
	# Fila de arriba: cara al pasillo, con puertas.
	w.append(_w(160, 360, 400, 360, "solid"))
	w.append(_w(540, 360, 760, 360, "solid"))
	w.append(_w(760, 360, 1000, 360, "glass"))
	w.append(_w(1140, 360, 1400, 360, "glass"))
	w.append(_w(1400, 360, 1640, 360, "planter"))
	w.append(_w(1880, 360, 2120, 360, "planter"))
	w.append(_w(2120, 360, 2300, 360, "solid"))
	w.append(_w(2440, 360, 2640, 360, "solid"))
	# Fila de abajo: cara al pasillo.
	w.append(_w(160, 560, 380, 560, "glass"))
	w.append(_w(520, 560, 760, 560, "glass"))
	w.append(_w(760, 560, 940, 560, "solid"))
	w.append(_w(1220, 560, 1400, 560, "solid"))
	w.append(_w(1400, 560, 1600, 560, "solid"))
	w.append(_w(1740, 560, 1960, 560, "solid"))
	w.append(_w(1960, 560, 2200, 560, "glass"))
	w.append(_w(2340, 560, 2640, 560, "glass"))
	# Divisiones entre salas (open space ↔ laboratorio y archivo ↔ finanzas con puerta).
	w.append(_w(760, -400, 760, 360, "solid"))
	w.append(_w(1400, -400, 1400, 360, "glass"))
	w.append(_w(2120, -400, 2120, 0, "glass"))
	w.append(_w(2120, 140, 2120, 360, "glass"))
	w.append(_w(760, 560, 760, 1320, "glass"))
	w.append(_w(1400, 560, 1400, 1320, "solid"))
	w.append(_w(1960, 560, 1960, 900, "solid"))
	w.append(_w(1960, 1040, 1960, 1320, "solid"))
	# ── Ala este ── El antiguo muro exterior (x = 2640) queda como muro interior
	# ciego: al laboratorio y a finanzas se sigue entrando por el pasillo.
	w.append(_w(2640, -400, 2640, 360, "solid"))
	w.append(_w(2640, 560, 2640, 1320, "solid"))
	w.append(_w(3160, -400, 3160, 360, "solid"))
	w.append(_w(3600, -400, 3600, 360, "solid"))
	w.append(_w(3280, 560, 3280, 1320, "solid"))
	# Fila de arriba (legal, RRHH, cuarto eléctrico): cara al pasillo, con puertas.
	w.append(_w(2640, 360, 2840, 360, "glass"))
	w.append(_w(2980, 360, 3160, 360, "glass"))
	w.append(_w(3160, 360, 3300, 360, "solid"))
	w.append(_w(3440, 360, 3600, 360, "solid"))
	w.append(_w(3600, 360, 3740, 360, "solid"))
	w.append(_w(3880, 360, 4040, 360, "solid"))
	# Fila de abajo (gimnasio y terraza).
	w.append(_w(2640, 560, 3060, 560, "glass"))
	w.append(_w(3200, 560, 3280, 560, "glass"))
	w.append(_w(3280, 560, 3360, 560, "glass"))
	w.append(_w(3500, 560, 4040, 560, "glass"))
	return w

## Mobiliario: tipo, huella (rect en px) y hacia dónde mira ("n", "s", "e", "o").
## solid = false: decoración sin colisión (alfombras, letreros).
static func props() -> Array:
	return [
		# ── Sala de seguridad ── (pista en -400,-150)
		{"type": "cctv_wall", "rect": Rect2(-610, -392, 420, 28), "face": "s"},
		{"type": "sysadmin_desk", "rect": Rect2(-530, -270, 260, 60), "face": "n"},
		{"type": "cabinets", "rect": Rect2(-630, -170, 36, 250), "face": "e"},
		{"type": "plant_big", "rect": Rect2(-215, 60, 44, 44)},
		# ── Recepción ── (pista en -410,340)
		{"type": "plant_big", "rect": Rect2(-150, -390, 44, 44)},
		{"type": "plant_big", "rect": Rect2(106, -390, 44, 44)},
		{"type": "reception", "rect": Rect2(-570, 220, 300, 60), "face": "s"},
		{"type": "kiosk", "rect": Rect2(96, 170, 50, 40), "face": "o"},
		{"type": "elevator", "rect": Rect2(-638, 430, 16, 130), "face": "e"},
		{"type": "elevator", "rect": Rect2(-638, 580, 16, 130), "face": "e"},
		{"type": "rug", "rect": Rect2(-600, 780, 440, 420), "solid": false, "color": "#1E3A5F"},
		{"type": "sofa", "rect": Rect2(-620, 840, 60, 240), "face": "e"},
		{"type": "coffee_table", "rect": Rect2(-470, 900, 110, 130)},
		{"type": "armchair", "rect": Rect2(-280, 860, 60, 60), "face": "o"},
		{"type": "armchair", "rect": Rect2(-280, 990, 60, 60), "face": "o"},
		{"type": "sofa", "rect": Rect2(-560, 1250, 260, 56), "face": "n"},
		{"type": "plant_big", "rect": Rect2(-630, 1265, 44, 44)},
		{"type": "plant_big", "rect": Rect2(106, 1265, 44, 44)},
		{"type": "plant_big", "rect": Rect2(-630, 135, 44, 44)},
		# ── Sala de servidores ── (pista en 460,120)
		{"type": "rack", "rect": Rect2(190, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(265, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(340, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(415, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(490, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(565, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(640, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(190, -210, 70, 50)},
		{"type": "rack", "rect": Rect2(265, -210, 70, 50)},
		{"type": "rack", "rect": Rect2(340, -210, 70, 50)},
		{"type": "rack", "rect": Rect2(490, -210, 70, 50)},
		{"type": "rack", "rect": Rect2(565, -210, 70, 50)},
		{"type": "rack", "rect": Rect2(640, -210, 70, 50)},
		{"type": "ups", "rect": Rect2(190, -40, 60, 44)},
		{"type": "ups", "rect": Rect2(255, -40, 60, 44)},
		{"type": "cooling", "rect": Rect2(715, -120, 36, 160)},
		{"type": "sysadmin_desk", "rect": Rect2(390, 170, 140, 56), "face": "n"},
		# ── Despacho del CEO ── (pistas en 1080,60 y 1260,230)
		{"type": "bookshelf", "rect": Rect2(840, -395, 320, 34)},
		{"type": "rug", "rect": Rect2(900, -170, 380, 300), "solid": false, "color": "#4A2C2A"},
		{"type": "exec_desk", "rect": Rect2(960, -60, 240, 70), "face": "s"},
		{"type": "exec_chair", "rect": Rect2(1055, -112, 50, 40), "face": "s"},
		{"type": "sofa", "rect": Rect2(778, -230, 56, 200), "face": "e"},
		{"type": "coffee_table", "rect": Rect2(860, -190, 70, 110)},
		{"type": "cabinets", "rect": Rect2(1362, -300, 30, 180), "face": "o"},
		{"type": "safe", "rect": Rect2(1326, 250, 56, 56)},
		{"type": "plant_big", "rect": Rect2(1348, -390, 44, 44)},
		{"type": "plant_big", "rect": Rect2(776, 300, 44, 44)},
		# ── Open space ── (pista en 1760,40)
		{"type": "desk_pod", "rect": Rect2(1440, -350, 200, 110)},
		{"type": "desk_pod", "rect": Rect2(1680, -350, 200, 110)},
		{"type": "desk_pod", "rect": Rect2(1440, -170, 200, 110)},
		{"type": "desk_pod", "rect": Rect2(1680, -170, 200, 110)},
		{"type": "whiteboard", "rect": Rect2(2092, -330, 20, 160), "face": "o"},
		{"type": "printer", "rect": Rect2(1440, 200, 64, 50)},
		{"type": "sofa", "rect": Rect2(1930, 170, 160, 56), "face": "n"},
		{"type": "plant_big", "rect": Rect2(2060, -100, 44, 44)},
		# ── Laboratorio de IA ── (pista en 2380,-110)
		{"type": "rack", "rect": Rect2(2160, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(2235, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(2310, -390, 70, 50)},
		{"type": "rack", "rect": Rect2(2385, -390, 70, 50)},
		{"type": "cooling", "rect": Rect2(2596, -260, 36, 160)},
		{"type": "holo_table", "rect": Rect2(2310, -60, 140, 100)},
		{"type": "lab_bench", "rect": Rect2(2160, 200, 200, 60), "face": "n"},
		{"type": "lab_bench", "rect": Rect2(2420, 200, 200, 60), "face": "n"},
		{"type": "plant_big", "rect": Rect2(2590, 0, 40, 40)},
		# ── Pasillo ──
		{"type": "rug", "rect": Rect2(220, 432, 3700, 56), "solid": false, "color": "#22304A"},
		{"type": "plant_big", "rect": Rect2(3984, 376, 44, 44)},
		{"type": "extinguisher", "rect": Rect2(3996, 506, 24, 24)},
		# ── Sala de juntas ── (pista en 460,1010)
		{"type": "rug", "rect": Rect2(220, 700, 480, 440), "solid": false, "color": "#1F2A44"},
		{"type": "meeting_table", "rect": Rect2(260, 800, 400, 170)},
		{"type": "tv_wall", "rect": Rect2(174, 780, 16, 220), "face": "e"},
		{"type": "cabinets", "rect": Rect2(300, 1276, 300, 36), "face": "n"},
		{"type": "plant_big", "rect": Rect2(700, 1260, 40, 40)},
		{"type": "plant_big", "rect": Rect2(180, 1260, 40, 40)},
		# ── Cafetería ── (pista en 1300,780: tras la cafetera)
		{"type": "counter", "rect": Rect2(1350, 700, 40, 400), "face": "o"},
		{"type": "fridge", "rect": Rect2(1350, 620, 40, 64)},
		{"type": "vending", "rect": Rect2(790, 580, 64, 40), "face": "s"},
		{"type": "vending", "rect": Rect2(864, 580, 64, 40), "face": "s"},
		{"type": "cafe_table", "rect": Rect2(860, 880, 80, 80)},
		{"type": "cafe_table", "rect": Rect2(1080, 880, 80, 80)},
		{"type": "cafe_table", "rect": Rect2(860, 1110, 80, 80)},
		{"type": "cafe_table", "rect": Rect2(1080, 1110, 80, 80)},
		{"type": "cafe_table", "rect": Rect2(1240, 1210, 70, 70)},
		{"type": "plant_big", "rect": Rect2(778, 1270, 40, 40)},
		# ── Archivo y reciclaje ── (pista en 1780,1205)
		{"type": "cabinets", "rect": Rect2(1412, 600, 40, 400), "face": "e"},
		{"type": "cabinets", "rect": Rect2(1914, 580, 40, 300), "face": "o"},
		{"type": "bookshelf", "rect": Rect2(1520, 820, 280, 34)},
		{"type": "boxes", "rect": Rect2(1480, 1250, 140, 50)},
		{"type": "bins", "rect": Rect2(1720, 1262, 180, 40), "face": "n"},
		{"type": "shredder", "rect": Rect2(1600, 600, 44, 34), "face": "s"},
		# ── Finanzas ── (pista en 2320,990)
		{"type": "desk_pod", "rect": Rect2(2020, 690, 200, 110)},
		{"type": "desk_pod", "rect": Rect2(2380, 690, 200, 110)},
		{"type": "exec_desk", "rect": Rect2(2220, 1040, 200, 64), "face": "n"},
		{"type": "printer", "rect": Rect2(1990, 980, 64, 50)},
		{"type": "cabinets", "rect": Rect2(2598, 900, 36, 300), "face": "o"},
		{"type": "safe", "rect": Rect2(2570, 1250, 56, 56)},
		{"type": "plant_big", "rect": Rect2(1980, 1265, 44, 44)},
		# ── Departamento legal ── (pista en 2900,-80)
		{"type": "law_shelf", "rect": Rect2(2672, -395, 456, 34)},
		{"type": "rug", "rect": Rect2(2900, -330, 240, 200), "solid": false, "color": "#3B2A1E"},
		{"type": "exec_desk", "rect": Rect2(2960, -250, 170, 64), "face": "s"},
		{"type": "exec_chair", "rect": Rect2(3020, -306, 50, 40), "face": "s"},
		{"type": "cabinets", "rect": Rect2(2654, -320, 36, 220), "face": "e"},
		{"type": "cabinets", "rect": Rect2(3110, -120, 36, 220), "face": "o"},
		{"type": "rug", "rect": Rect2(2670, 40, 220, 220), "solid": false, "color": "#2E3B2F"},
		{"type": "meeting_small", "rect": Rect2(2690, 80, 180, 140)},
		{"type": "scales", "rect": Rect2(3100, 290, 44, 44)},
		{"type": "plant_big", "rect": Rect2(2656, 296, 44, 44)},
		# ── Recursos humanos ── (pista en 3380,0)
		{"type": "desk_pod", "rect": Rect2(3196, -350, 200, 110)},
		{"type": "notice_board", "rect": Rect2(3420, -394, 160, 14), "face": "s"},
		{"type": "office_desk", "rect": Rect2(3440, -230, 136, 60), "face": "n"},
		{"type": "office_desk", "rect": Rect2(3440, 110, 136, 60), "face": "n"},
		{"type": "waiting_chairs", "rect": Rect2(3174, 40, 44, 220), "face": "e"},
		{"type": "water_cooler", "rect": Rect2(3550, -60, 36, 36)},
		{"type": "cabinets", "rect": Rect2(3176, 306, 110, 36), "face": "n"},
		{"type": "plant_big", "rect": Rect2(3546, 300, 44, 44)},
		# ── Cuarto eléctrico ── (pista en 3820,-160)
		{"type": "elec_panel", "rect": Rect2(3624, -394, 300, 32), "face": "s"},
		{"type": "elec_panel", "rect": Rect2(3612, -250, 32, 300), "face": "e"},
		{"type": "ups_big", "rect": Rect2(3950, -360, 72, 260), "face": "o"},
		{"type": "ups", "rect": Rect2(3958, -40, 60, 44)},
		{"type": "ups", "rect": Rect2(3958, 14, 60, 44)},
		{"type": "cables", "rect": Rect2(3660, -360, 290, 400), "solid": false},
		{"type": "cable_reel", "rect": Rect2(3660, 250, 70, 70)},
		{"type": "emergency_light", "rect": Rect2(3612, 100, 14, 40), "solid": false, "face": "e", "h": 0.45},
		{"type": "emergency_light", "rect": Rect2(4016, 150, 14, 40), "solid": false, "face": "o", "h": 1.8},
		{"type": "emergency_light", "rect": Rect2(3936, -390, 40, 12), "solid": false, "face": "s", "h": 2.3},
		# ── Gimnasio ── (pista en 2960,1000: junto a la taquilla 14)
		{"type": "treadmill", "rect": Rect2(2672, 610, 64, 140), "face": "n"},
		{"type": "treadmill", "rect": Rect2(2756, 610, 64, 140), "face": "n"},
		{"type": "treadmill", "rect": Rect2(2840, 610, 64, 140), "face": "n"},
		{"type": "rug", "rect": Rect2(2670, 840, 180, 200), "solid": false, "color": "#6E3328"},
		{"type": "rug", "rect": Rect2(2920, 600, 120, 290), "solid": false, "color": "#2F6B55"},
		{"type": "weight_bench", "rect": Rect2(2730, 880, 50, 120), "face": "n"},
		{"type": "weight_bench", "rect": Rect2(3120, 800, 50, 120), "face": "n"},
		{"type": "dumbbells", "rect": Rect2(2656, 1090, 40, 200), "face": "e"},
		{"type": "lockers", "rect": Rect2(2880, 926, 200, 36), "face": "s", "first": 12},
		{"type": "lockers", "rect": Rect2(3230, 680, 36, 240), "face": "o", "first": 1},
		{"type": "bench", "rect": Rect2(2900, 1150, 160, 36)},
		{"type": "water_cooler", "rect": Rect2(3226, 1256, 36, 36)},
		{"type": "plant_big", "rect": Rect2(3020, 584, 34, 34)},
		# ── Terraza ── (pista en 3700,1080: junto a la maceta)
		{"type": "festoon", "rect": Rect2(3324, 606, 670, 668), "solid": false},
		{"type": "planter_big", "rect": Rect2(3296, 578, 56, 56)},
		{"type": "planter_big", "rect": Rect2(3964, 578, 60, 60)},
		{"type": "planter_big", "rect": Rect2(3742, 1046, 70, 70)},
		{"type": "planter_big", "rect": Rect2(3964, 1246, 60, 60)},
		{"type": "planter_big", "rect": Rect2(3296, 1246, 56, 56)},
		{"type": "sofa", "rect": Rect2(3580, 578, 200, 56), "face": "s", "color": "#C9B79C"},
		{"type": "coffee_table", "rect": Rect2(3630, 676, 110, 64)},
		{"type": "patio_table", "rect": Rect2(3830, 760, 100, 100)},
		{"type": "lounger", "rect": Rect2(3380, 1140, 56, 130), "face": "s"},
		{"type": "lounger", "rect": Rect2(3470, 1140, 56, 130), "face": "s"},
		{"type": "lounger", "rect": Rect2(3560, 1140, 56, 130), "face": "s"},
		{"type": "telescope", "rect": Rect2(3964, 990, 40, 40)},
	]

## Rectángulos de colisión: muros (con huecos de puertas) y muebles sólidos.
static func colliders() -> Array:
	var out := []
	for w in walls():
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var r := Rect2(a, Vector2.ZERO).expand(b).grow(WALL / 2.0)
		out.append(r)
	for p in props():
		if p.get("solid", true):
			out.append(p["rect"])
	return out

## Sala que contiene un punto (la primera que lo tenga), o {} si cae fuera.
static func room_at(p: Vector2) -> Dictionary:
	for room in rooms():
		if (room["rect"] as Rect2).has_point(p):
			return room
	return {}
