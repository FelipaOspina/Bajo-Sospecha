shader_type canvas_item;
render_mode blend_premul_alpha;
// Hoja horneada de ChibiBaker: el SubViewport la guarda con el alfa ya multiplicado, así
// que se mezcla en modo premultiplicado (si no, los bordes salen oscuros). El color del
// vértice (modulate) se aplica aparte porque en fragment() COLOR ya trae la textura.
// Godot pasa la textura a lineal él solo en los viewports con HDR 2D: el chibi horneado
// se ve igual que el chibi en vivo en Forward+, Mobile y Compatibility.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * tint;
}
