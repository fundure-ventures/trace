"""Export aligned, independently lit RGBA layers without modifying the blend.

Run: blender --background design/app-icon/trace-e.blend --python-exit-code 1 \
--python design/app-icon/export_blender_layers.py

Outputs use the original full canvas and camera, ordered back to front.
Lighting and self-shading are baked in; inter-layer shadows and refraction are
not. Stacking these PNGs cannot exactly reproduce the full-scene render or
dynamically blur content behind the vellum. These are artwork layers, not a
validated Icon Composer document.
"""

import json
from pathlib import Path

import bpy


def export_layers():
    scene = bpy.data.scenes["Trace E - 03-rainbow-rim"]
    output = Path(__file__).resolve().parent / "layers"
    layers = [
        ("01-window-chrome.png", "01 Mac window"),
        ("02-paper.png", "02 Tracing paper"),
        ("03-trace.png", "03 Voice ink"),
        ("04-pen.png", "04 Crayon"),
    ]
    groups = [(filename, scene.collection.children[name]) for filename, name in layers]
    assert scene.camera is not None
    assert scene.render.resolution_percentage == 100
    assert all(len(group.objects) for _, group in groups)
    output.mkdir(exist_ok=True)
    render = scene.render
    visibility = [(obj, obj.hide_render) for obj in scene.objects]
    settings = (render.filepath, render.film_transparent, render.use_border,
                render.image_settings.file_format, render.image_settings.color_mode,
                render.image_settings.color_depth)
    try:
        render.film_transparent = True
        render.use_border = False
        render.image_settings.file_format = "PNG"
        render.image_settings.color_mode = "RGBA"
        render.image_settings.color_depth = "8"
        for filename, group in groups:
            for obj, hidden in visibility:
                if obj.type not in {"CAMERA", "LIGHT"}:
                    obj.hide_render = hidden or obj.name not in group.objects
            render.filepath = str(output / filename)
            bpy.ops.render.render(write_still=True, scene=scene.name)
            assert (output / filename).is_file(), filename
    finally:
        for obj, hidden in visibility:
            obj.hide_render = hidden
        (render.filepath, render.film_transparent, render.use_border,
         render.image_settings.file_format, render.image_settings.color_mode,
         render.image_settings.color_depth) = settings
    manifest = {
        "source": "../trace-e.blend",
        "scene": scene.name,
        "canvas": [render.resolution_x, render.resolution_y],
        "format": "8-bit RGBA PNG, straight alpha",
        "alignment": "Full original canvas; no cropping or repositioning",
        "layers_back_to_front": [filename for filename, _ in layers],
        "rendering": "Independent objects with original lighting and self-shading",
        "limitations": [
            "No inter-layer shadows, reflected color or refracted background",
            "Paper blur and translucency are not dynamic PNG effects",
            "Recomposition is not pixel-identical to the full-scene render",
            "Not a validated native platform icon",
        ],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    export_layers()
