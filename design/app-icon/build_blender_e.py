"""Build concept E in a new scene without modifying existing Blender scenes.

Run in Blender's Scripting workspace. Rendering/saving is intentionally separate.
"""

import math

import bpy
from mathutils import Vector


def material(name, color, roughness=0.5, grain=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    if grain:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.noise_dimensions = "3D"
        noise.inputs["Scale"].default_value = 220
        noise.inputs["Detail"].default_value = 3
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.24
        bump.inputs["Distance"].default_value = grain
        mat.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        mat.node_tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def mesh_object(name, vertices, faces, collection, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def rounded_panel(name, width, height, radius, z, collection, mat, center=(0, 0)):
    vertices = []
    for cx, cy, start in (
        (width / 2 - radius, height / 2 - radius, 0),
        (-width / 2 + radius, height / 2 - radius, 90),
        (-width / 2 + radius, -height / 2 + radius, 180),
        (width / 2 - radius, -height / 2 + radius, 270),
    ):
        for step in range(17):
            angle = math.radians(start + step * 90 / 16)
            vertices.append((
                center[0] + cx + radius * math.cos(angle),
                center[1] + cy + radius * math.sin(angle),
                z,
            ))
    obj = mesh_object(name, vertices, [tuple(range(len(vertices)))], collection, mat)
    solid = obj.modifiers.new("Thin shell", "SOLIDIFY")
    solid.thickness = 0.055
    bevel = obj.modifiers.new("Soft edge", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 3
    return obj


def paper_position(x, y):
    # Bend only the diagonal lower-left corner; preserve surface arc length.
    distance = max(0, 2.8 - ((x + 2.95) + (y + 3.45))) / math.sqrt(2)
    radius = 0.70
    angle = distance / radius
    inset = (distance - radius * math.sin(angle)) / math.sqrt(2)
    z = 0.25 + radius * (1 - math.cos(angle))
    x, y = (x + inset) * 1.22, (y + inset) * 1.05
    tilt = math.radians(9)
    return Vector((
        x * math.cos(tilt) - y * math.sin(tilt),
        x * math.sin(tilt) + y * math.cos(tilt) - 0.40,
        z,
    ))


def build_scene():
    scene = bpy.data.scenes.new("Trace E - material study")
    bpy.context.window.scene = scene
    groups = {}
    for name in ("01 Mac window", "02 Tracing paper", "03 Voice ink", "04 Crayon", "Studio"):
        group = bpy.data.collections.new(name)
        scene.collection.children.link(group)
        groups[name] = group

    white = material("E - porcelain white", (0.88, 0.88, 0.865), 0.65)
    silver = material("E - satin window edge", (0.53, 0.55, 0.58), 0.34)
    header = material("E - macOS title bar", (0.72, 0.73, 0.75), 0.52)
    black = material("E - charcoal wax wrapper", (0.005, 0.006, 0.007), 0.48, 0.012)
    black.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value = 0.4
    paper = material("E - translucent vellum", (0.89, 0.88, 0.83), 0.78, 0.006)
    for mat, low, high in (
        (paper, (0.81, 0.80, 0.76, 1), (0.89, 0.88, 0.84, 1)),
        (black, (0.002, 0.003, 0.004, 1), (0.012, 0.013, 0.014, 1)),
    ):
        nodes = mat.node_tree.nodes
        noise = next(n for n in nodes if n.bl_idname == "ShaderNodeTexNoise")
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.name = "Material grain tones"
        ramp.color_ramp.elements[0].position = 0.28
        ramp.color_ramp.elements[0].color = low
        ramp.color_ramp.elements[1].position = 0.72
        ramp.color_ramp.elements[1].color = high
        mat.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        mat.node_tree.links.new(ramp.outputs["Color"], nodes.get("Principled BSDF").inputs["Base Color"])
    shader = paper.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Transmission Weight"].default_value = 0.16
    shader.inputs["IOR"].default_value = 1.35
    shader.inputs["Subsurface Weight"].default_value = 0.07
    shader.inputs["Subsurface Scale"].default_value = 0.025
    colors = [(0.83, 0.018, 0.012), (1.0, 0.58, 0.009),
              (0.025, 0.43, 0.065), (0.015, 0.17, 0.78)]
    wax = [material("E - wax " + name, color, 0.6, 0.012)
           for name, color in zip(("red", "yellow", "green", "blue"), colors)]

    window = groups["01 Mac window"]
    rounded_panel("Window silver boundary", 6.8, 7.05, 0.24, 0.08, window, silver, (-0.45, 0.30))
    rounded_panel("Blank document", 6.75, 7.0, 0.22, 0.105, window, white, (-0.45, 0.30))
    rounded_panel("Compact title bar", 6.74, 0.62, 0.18, 0.13, window, header, (-0.45, 3.48))
    rounded_panel("Title bar hairline", 6.71, 0.012, 0.004, 0.14, window, silver, (-0.45, 3.17))
    for index, mat in enumerate(wax[:3]):
        cx, cy, r = -3.43 + index * 0.34, 3.48, 0.105
        vertices = [(cx + r * math.cos(i * math.tau / 64),
                     cy + r * math.sin(i * math.tau / 64), 0.165) for i in range(64)]
        dot = mesh_object("Traffic light " + str(index + 1), vertices, [tuple(range(64))], window, mat)
        solid = dot.modifiers.new("Button depth", "SOLIDIFY")
        solid.thickness = 0.015
    for obj in window.objects:
        for vertex in obj.data.vertices:
            vertex.co.x = (vertex.co.x + 0.45) * 1.12 - 0.10
            vertex.co.y = (vertex.co.y - 0.30) * 1.08 * 1.065 + 0.55

    vertices, faces = [], []
    nx, ny = 100, 116
    for j in range(ny + 1):
        for i in range(nx + 1):
            vertices.append(paper_position(-2.95 + 5.9 * i / nx, -3.45 + 6.9 * j / ny))
    for j in range(ny):
        for i in range(nx):
            k = j * (nx + 1) + i
            faces.append((k, k + 1, k + nx + 2, k + nx + 1))
    sheet = mesh_object("Continuous curled vellum", vertices, faces, groups["02 Tracing paper"], paper)
    for polygon in sheet.data.polygons:
        polygon.use_smooth = True
    solid = sheet.modifiers.new("Paper thickness", "SOLIDIFY")
    solid.thickness = 0.008

    # A thin ribbon carries the color and pressure, not a round plastic tube.
    controls = [
        ((-2.50, -0.93), (-2.05, -0.65), (-1.94, 1.22), (-1.28, 1.22)),
        ((-1.28, 1.22), (-0.62, 1.22), (-0.85, -1.13), (-0.40, -1.13)),
        ((-0.40, -1.13), (0.03, -1.13), (0.01, -0.22), (0.40, -0.22)),
        ((0.40, -0.22), (0.68, -0.22), (0.76, -1.08), (1.03, -0.82)),
    ]
    controls = [tuple((p[0]*1.12/1.22 + 0.15*math.cos(math.radians(9))/1.22,
                       p[1] - 0.15*math.sin(math.radians(9))/1.05)
                      for p in control) for control in controls]
    controls[0] = ((-2.73, controls[0][0][1]), *controls[0][1:])
    centers = []
    for control in controls:
        a, b, c, d = [Vector(point) for point in control]
        for step in range(70):
            t = step / 70
            centers.append((1-t)**3*a + 3*(1-t)**2*t*b + 3*(1-t)*t*t*c + t**3*d)
    centers.append(Vector(controls[-1][-1]))
    vertices, faces, vertex_colors = [], [], []
    stops = [(0, colors[0]), (0.20, colors[0]), (0.33, colors[1]),
             (0.50, colors[2]), (0.70, colors[2]), (1, colors[3])]
    for i, point in enumerate(centers):
        t = i / (len(centers) - 1)
        tangent = centers[min(i + 1, len(centers) - 1)] - centers[max(i - 1, 0)]
        normal = Vector((-tangent.y, tangent.x)).normalized()
        width = (0.067 + 0.025 * math.sin(t * math.tau * 1.4)**2) * min(1, t * 17 + 0.015)
        width *= 1 + 0.04*math.sin(i*2.39) + 0.02*math.sin(i*7.13)
        for left, right in zip(stops, stops[1:]):
            if left[0] <= t <= right[0]:
                blend = (t-left[0])/(right[0]-left[0])
                color = tuple(left[1][k]*(1-blend) + right[1][k]*blend for k in range(3))
                break
        for sign in (-1, 1):
            xy = point + sign * width * normal
            position = paper_position(xy.x, xy.y)
            position.z += 0.008
            vertices.append(position)
            vertex_colors.append((*color, 1))
        if i:
            k = i * 2
            faces.append((k-2, k, k+1, k-1))
    ink = material("E - gradient wax stroke", (1, 1, 1), 0.75, 0.01)
    stroke = mesh_object("Two-pulse pressure ribbon", vertices, faces, groups["03 Voice ink"], ink)
    attribute = stroke.data.color_attributes.new(name="Wax gradient", type="FLOAT_COLOR", domain="POINT")
    for datum, color in zip(attribute.data, vertex_colors):
        datum.color = color
    node = ink.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Wax gradient"
    noise = next(n for n in ink.node_tree.nodes if n.bl_idname == "ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 260
    ramp = ink.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.name = "Wax grain breakup"
    ramp.color_ramp.elements[0].position = 0.49
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.70
    ramp.color_ramp.elements[1].color = (0.65, 0.65, 0.65, 1)
    mix = ink.node_tree.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MIX"
    mix.inputs["Color2"].default_value = (0.83, 0.82, 0.77, 1)
    ink.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    ink.node_tree.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    ink.node_tree.links.new(node.outputs["Color"], mix.inputs["Color1"])
    ink.node_tree.links.new(mix.outputs["Color"], ink.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])

    tip = paper_position(*controls[-1][-1])
    tip.z += 0.008
    axis = Vector((2.05, 3.50, 5.0))
    rotation = axis.to_track_quat("Z", "Y")
    length = axis.length
    crayon = groups["04 Crayon"]
    # Lathed barrel with rolled edges and a closed, softly rounded end.
    profile = [(0.90, 0.44), (0.94, 0.50), (0.99, 0.52),
               (length-0.18, 0.58), (length-0.09, 0.565), (length, 0.50),
               (length+0.045, 0.37), (length+0.065, 0.18), (length+0.07, 0.015)]
    vertices, faces = [], []
    segments = 96
    for height, radius in profile:
        for i in range(segments):
            angle = math.tau * i / segments
            vertices.append(tip + rotation @ Vector((radius*math.cos(angle), radius*math.sin(angle), height)))
    for j in range(len(profile)-1):
        for i in range(segments):
            a = j * segments + i
            b = j * segments + (i+1) % segments
            faces.append((a, b, b+segments, a+segments))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(profile)-1)*segments+i for i in range(segments)))
    body = mesh_object("Raised matte crayon barrel", vertices, faces, crayon, black)
    for polygon in body.data.polygons:
        polygon.use_smooth = len(polygon.vertices) == 4
    # Four real wax wedges, each editable independently.
    view = rotation.inverted() @ (Vector((0, -9, 22))-tip)
    front = math.atan2(view.y, view.x)
    bounds = [front-math.pi, front-math.pi/6, front+math.pi/6,
              front+math.pi/3, front+math.pi]
    for sector, mat in enumerate(wax):
        vertices = [tip]
        for i in range(25):
            angle = bounds[sector] + (bounds[sector+1]-bounds[sector])*i/24
            vertices.append(tip + rotation @ Vector((0.455*math.cos(angle), 0.455*math.sin(angle), 0.94)))
        vertices.append(tip + rotation @ Vector((0, 0, 0.94)))
        faces = [(0, i+1, i+2) for i in range(24)]
        faces += [(0, 26, 1), (0, 25, 26), tuple(range(1, 27))]
        wedge = mesh_object("Wax tip " + str(sector+1), vertices, faces, crayon, mat)
        for polygon in wedge.data.polygons[:24]:
            polygon.use_smooth = True

    studio = groups["Studio"]
    backdrop = rounded_panel("White backdrop", 200, 200, 0.2, -0.11, studio, white)
    # Keep a studio floor available, but omit its oversized cast shadow in icon exports.
    backdrop.hide_render = True
    camera_data = bpy.data.cameras.new("E orthographic camera")
    camera = bpy.data.objects.new("E camera", camera_data)
    studio.objects.link(camera)
    target = Vector((0, 0, 0.45))
    camera.location = (0, -9, 22)
    camera.rotation_euler = (target-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 9.7
    scene.camera = camera
    for name, location, power, size in (
        ("Key softbox", (-5, -3, 10), 1100, 5),
        ("Fill softbox", (5, 0, 8), 350, 6),
        ("Rim softbox", (0, 7, 9), 500, 5),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size = power, "DISK", size
        obj = bpy.data.objects.new(name, data)
        studio.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (-obj.location).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("E neutral studio")
    world.color = (0.55, 0.55, 0.55)
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 1536
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = "//trace-e.png"
    scene.view_settings.view_transform = "Standard"
    scene["design_reference"] = "Approved generated E: a3ed518d-c235-4671-a18b-1a57c10963ae.png"
    scene["delivery_status"] = "Editable material study; not integrated or platform-mask verified"
    return scene


if __name__ == "__main__":
    build_scene()
