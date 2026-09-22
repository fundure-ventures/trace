"""Build concept E and four lighting studies without modifying existing scenes.

Run in Blender's Scripting workspace. The studies share artwork and camera, not
lights or worlds. Rainbow lighting is selected for the main preview.
Rendering/saving is intentionally separate.
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


def mac_window(collection, silver, white, header):
    width, height, radius = 6.8*1.12, 7.05*1.08*1.065, 0.27
    cx, cy = -0.10, 0.55
    divider = (3.17-0.30)*1.08*1.065 + cy

    def outline(inset, z):
        w, h, r = width-2*inset, height-2*inset, radius-inset
        points = []
        for x, y, start in (
            (w/2-r, h/2-r, 0), (-w/2+r, h/2-r, 90),
            (-w/2+r, -h/2+r, 180), (w/2-r, -h/2+r, 270),
        ):
            for step in range(33):
                angle = math.radians(start + step*90/32)
                points.append((cx+x+r*math.cos(angle), cy+y+r*math.sin(angle), z))
        split = []
        for a, b in zip(points, points[1:]+points[:1]):
            split.append(a)
            if (a[1]-divider)*(b[1]-divider) < 0:
                t = (divider-a[1])/(b[1]-a[1])
                split.append((a[0]+t*(b[0]-a[0]), divider, z))
        return split

    # Header and document share one coplanar face boundary; only the outside is beveled.
    profiles = [(0.04, -0.035), (0.012, -0.025), (0, 0.005), (0, 0.055)]
    profiles += [(0.06*(1-math.cos(a)), 0.055+0.075*math.sin(a))
                 for a in (math.pi*step/16 for step in range(1, 9))]
    rings = [outline(inset, z) for inset, z in profiles]
    count = len(rings[0])
    assert all(len(ring) == count for ring in rings)
    vertices = [point for ring in rings for point in ring]
    faces = [tuple(reversed(range(count)))]
    for j in range(len(rings)-1):
        for i in range(count):
            a, b = j*count+i, j*count+(i+1) % count
            faces.append((a, b, b+count, a+count))
    offset = (len(rings)-1)*count
    faces.append(tuple(offset+i for i, p in enumerate(rings[-1]) if p[1] <= divider))
    faces.append(tuple(offset+i for i, p in enumerate(rings[-1]) if p[1] >= divider))
    shell = mesh_object("Unified beveled Mac window", vertices, faces, collection, silver)
    shell.data.materials.append(white)
    shell.data.materials.append(header)
    for polygon in shell.data.polygons[1:-2]:
        polygon.use_smooth = True
    shell.data.polygons[-2].material_index = 1
    shell.data.polygons[-1].material_index = 2

    def linear_rgb(rgb):
        return tuple(c/255/12.92 if c/255 <= 0.04045 else ((c/255+0.055)/1.055)**2 for c in rgb)

    # Sampled from the supplied golden reference after converting its ICC profile to sRGB.
    for index, (name, top_rgb, bottom_rgb, neutral_gain) in enumerate((
        ("close", (252, 110, 101), (246, 142, 134), (1.04, 0.81, 0.79)),
        ("minimize", (252, 188, 45), (254, 211, 73), (1.06, 0.97, 0.59)),
        ("zoom", (103, 208, 57), (156, 221, 127), (0.82, 0.98, 0.70)),
    )):
        top, bottom = linear_rgb(top_rgb), linear_rgb(bottom_rgb)
        # Extend the interior samples to the rim, then compensate measured neutral-rig albedo gain.
        top, bottom = (
            tuple(max(0, t-0.3*(b-t))*0.84*g for t, b, g in zip(top, bottom, neutral_gain)),
            tuple(min(1, b+0.3*(b-t))*0.84*g for t, b, g in zip(top, bottom, neutral_gain)),
        )
        lens = material("E - Aqua " + name, top, 0.60)
        shader = lens.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Specular IOR Level"].default_value = 0.008
        rim = material("E - Aqua rim " + name, tuple(c*0.76 for c in top), 0.55)
        x = (-3.43+index*0.36+0.45)*1.12-0.10
        y = (3.48-0.30)*1.08*1.065+0.55
        profile = [(0.123, 0.134), (0.123, 0.141), (0.114, 0.146),
                   (0.102, 0.151), (0.070, 0.157), (0.035, 0.159), (0.002, 0.160)]
        vertices, faces = [], []
        segments = 64
        for r, z in profile:
            for i in range(segments):
                angle = math.tau*i/segments
                vertices.append((x+r*math.cos(angle), y+r*math.sin(angle), z))
        faces.append(tuple(reversed(range(segments))))
        for j in range(len(profile)-1):
            for i in range(segments):
                a, b = j*segments+i, j*segments+(i+1) % segments
                faces.append((a, b, b+segments, a+segments))
        faces.append(tuple((len(profile)-1)*segments+i for i in range(segments)))
        button = mesh_object("Aqua " + name, vertices, faces, collection, rim)
        button.data.materials.append(lens)
        attribute = button.data.color_attributes.new(name="Control gradient", type="FLOAT_COLOR", domain="POINT")
        for vertex, datum in zip(button.data.vertices, attribute.data):
            t = max(0, min(1, (1-(vertex.co.y-y)/0.114)/2))
            datum.color = (*(top[k]*(1-t)+bottom[k]*t for k in range(3)), 1)
        color_node = lens.node_tree.nodes.new("ShaderNodeVertexColor")
        color_node.layer_name = "Control gradient"
        lens.node_tree.links.new(color_node.outputs["Color"], shader.inputs["Base Color"])
        for polygon in button.data.polygons:
            polygon.use_smooth = len(polygon.vertices) == 4
            if polygon.index > 2*segments:
                polygon.material_index = 1


def paper_position(x, y):
    # Bend only the diagonal lower-left corner; preserve surface arc length.
    distance = max(0, 2.7 - ((x + 2.95) + (y + 3.45))) / math.sqrt(2)
    radius = 0.75
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
    silver = material("E - satin window edge", (0.68, 0.70, 0.73), 0.24)
    silver.node_tree.nodes.get("Principled BSDF").inputs["Metallic"].default_value = 0.38
    header = material("E - macOS title bar", (0.63, 0.66, 0.71), 0.52)
    black = material("E - charcoal wax wrapper", (0.005, 0.006, 0.007), 0.48, 0.012)
    black.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value = 0.4
    paper = material("E - translucent vellum", (0.97, 0.97, 0.94), 0.48, 0.006)
    for mat, low, high in (
        (paper, (0.90, 0.90, 0.87, 1), (0.97, 0.97, 0.94, 1)),
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
    shader.inputs["Transmission Weight"].default_value = 0.68
    shader.inputs["IOR"].default_value = 1.35
    shader.inputs["Subsurface Weight"].default_value = 0.025
    shader.inputs["Subsurface Scale"].default_value = 0.025
    shader.inputs["Specular IOR Level"].default_value = 0.25
    # Rough transmission blurs the window; diffuse scattering keeps the sheet fibrous, not glassy.
    nodes, links = paper.node_tree.nodes, paper.node_tree.links
    translucent = nodes.new("ShaderNodeBsdfTranslucent")
    translucent.name = "Diffuse fiber transmission"
    mix = nodes.new("ShaderNodeMixShader")
    mix.name = "Vellum surface and fiber scattering"
    mix.inputs[0].default_value = 0.12
    links.new(nodes["Material grain tones"].outputs["Color"], translucent.inputs["Color"])
    links.new(nodes["Bump"].outputs["Normal"], translucent.inputs["Normal"])
    links.new(shader.outputs["BSDF"], mix.inputs[1])
    links.new(translucent.outputs["BSDF"], mix.inputs[2])
    links.new(mix.outputs[0], nodes["Material Output"].inputs["Surface"])
    colors = [(0.83, 0.018, 0.012), (1.0, 0.58, 0.009),
              (0.025, 0.43, 0.065), (0.015, 0.17, 0.78)]
    wax = [material("E - wax " + name, color, 0.6, 0.012)
           for name, color in zip(("red", "yellow", "green", "blue"), colors)]

    window = groups["01 Mac window"]
    mac_window(window, silver, white, header)

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
        ((-1.28, 1.22), (-0.62, 1.22), (-0.85, -1.13), (-0.48, -1.13)),
        ((-0.48, -1.13), (-0.04, -1.13), (-0.04, -0.06), (0.35, -0.06)),
        ((0.35, -0.06), (0.66, -0.06), (0.76, -1.08), (1.03, -0.82)),
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
             (0.50, colors[2]), (0.64, colors[2]), (1, colors[3])]
    for i, point in enumerate(centers):
        t = i / (len(centers) - 1)
        tangent = centers[min(i + 1, len(centers) - 1)] - centers[max(i - 1, 0)]
        normal = Vector((-tangent.y, tangent.x)).normalized()
        width = (0.067 + 0.025 * math.sin(t * math.tau * 1.4)**2) * min(1, t * 17 + 0.015)
        if t > 0.5:
            width *= 1 + 0.16 * math.sin(math.pi * (t-0.5)/0.5)**2
        width *= 1 + 0.09*math.sin(t*math.tau*3.4+0.6) + 0.04*math.sin(t*math.tau*7.3)
        width *= 1 + 0.015*math.sin(i*2.39) + 0.007*math.sin(i*7.13)
        point = point + normal * (0.014 * math.sin(t*math.tau*6) * math.sin(math.pi*t))
        for left, right in zip(stops, stops[1:]):
            if left[0] <= t <= right[0]:
                blend = (t-left[0])/(right[0]-left[0])
                blend = blend*blend*(3-2*blend)
                color = tuple(left[1][k]*(1-blend) + right[1][k]*blend for k in range(3))
                break
        for sign in (-1, 1):
            xy = point + sign * width * normal
            position = paper_position(xy.x, xy.y)
            position.z += 0.003
            vertices.append(position)
            vertex_colors.append((*color, 1))
        if i:
            k = i * 2
            faces.append((k-2, k, k+1, k-1))
    # Round the contact patch under the nib instead of ending with a cut edge.
    left, right = len(vertices)-2, len(vertices)-1
    center_index = len(vertices)
    endpoint = paper_position(*centers[-1])
    endpoint.z += 0.003
    vertices.append(endpoint)
    vertex_colors.append((*color, 1))
    faces[-1] = (left-2, left, center_index, right, right-2)
    tangent = (centers[-1]-centers[-2]).normalized()
    normal = Vector((-tangent.y, tangent.x))
    arc = [left]
    for step in range(1, 16):
        angle = -math.pi/2 + math.pi*step/16
        xy = centers[-1] + width*(math.cos(angle)*tangent + math.sin(angle)*normal)
        position = paper_position(*xy)
        position.z += 0.003
        arc.append(len(vertices))
        vertices.append(position)
        vertex_colors.append((*color, 1))
    arc.append(right)
    faces.extend((center_index, a, b) for a, b in zip(arc, arc[1:]))
    ink = material("E - gradient wax stroke", (1, 1, 1), 0.75, 0.003)
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
    ramp.color_ramp.elements[0].position = 0.51
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = 0.74
    ramp.color_ramp.elements[1].color = (0.42, 0.42, 0.42, 1)
    mix = ink.node_tree.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MIX"
    mix.inputs["Color2"].default_value = (0.83, 0.82, 0.77, 1)
    ink.node_tree.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    ink.node_tree.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    ink.node_tree.links.new(node.outputs["Color"], mix.inputs["Color1"])
    ink.node_tree.links.new(mix.outputs["Color"], ink.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])

    tip = paper_position(*controls[-1][-1])
    tip.z += 0.003
    axis = Vector((2.05, 3.50, 5.0))
    rotation = axis.to_track_quat("Z", "Y")
    length = axis.length
    crayon = groups["04 Crayon"]
    # Lathed barrel with rolled edges and a closed, softly rounded end.
    profile = [(0.90, 0.44), (0.94, 0.50), (0.99, 0.52), (length-0.18, 0.58)]
    profile += [(length-0.18+0.25*math.sin(a), 0.58*math.cos(a))
                for a in ((math.pi/2-0.003)*step/16 for step in range(1, 17))]
    vertices, faces = [], []
    segments = 144
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
        ("Key softbox", (-5, 4, 10), 700, 7),
        ("Fill softbox", (5, -3, 8), 600, 8),
        ("Rim softbox", (0, 7, 9), 200, 6),
        ("Curl bounce", (-3.5, -4, 2.8), 80, 5),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size = power, "DISK", size
        obj = bpy.data.objects.new(name, data)
        studio.objects.link(obj)
        obj.location = location
        light_target = Vector((-1.6, -2.4, 0.35)) if name == "Curl bounce" else Vector((0, 0, 0))
        obj.rotation_euler = (light_target-obj.location).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("E neutral studio")
    world.color = (0.55, 0.55, 0.55)
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 256
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 1536
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = "//trace-e.png"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = 0.2
    scene["design_reference"] = "Approved generated E: a3ed518d-c235-4671-a18b-1a57c10963ae.png"
    scene["craft_reference_ids"] = "028-018, 064-010, 039-012, 062-005, 066-016"
    scene["delivery_status"] = "Editable material study; not integrated or platform-mask verified"
    return scene


def lighting_variants(baseline):
    # Geometry, camera, and materials are shared; every rig and world is independent.
    neutral = (1, 1, 1)
    rigs = {
        "01-soft-daylight": [
            ("Key softbox", (-6, 3, 12), 900, 9, neutral),
            ("Fill softbox", (5, -4, 8), 700, 10, neutral),
            ("Rim softbox", (0, 8, 10), 150, 8, neutral),
            ("Curl bounce", (-3.5, -4, 2.8), 80, 5, neutral),
        ],
        "02-warm-cool": [
            ("Key softbox", (-5, 2, 9), 648, 6, (1, 0.84, 0.67)),
            ("Fill softbox", (5, -3, 8), 576, 8, (0.68, 0.83, 1)),
            ("Rim softbox", (0, 7, 9), 144, 5, neutral),
            ("Curl bounce", (-3.5, -4, 2.8), 57.6, 5, neutral),
        ],
        "03-rainbow-rim": [
            ("Key softbox", (-5, 4, 10), 364, 7, neutral),
            ("Fill softbox", (5, -3, 8), 308, 8, neutral),
            ("Rim softbox", (4, 5, 6), 235.2, 4, (0.30, 0.56, 1)),
            ("Curl bounce", (-3.5, -4, 2.8), 35, 5, neutral),
            ("Red reflection", (-4, 1, 5), 145.6, 3, (1, 0.25, 0.20)),
            ("Yellow reflection", (-4, -4, 4), 28, 4, (1, 0.75, 0.25)),
            ("Green reflection", (3, -3, 5), 100.8, 4, (0.24, 1, 0.46)),
        ],
        "04-overcast": [
            ("Key softbox", (0, 1, 13), 1000, 12, neutral),
            ("Fill softbox", (-5, -4, 7), 500, 10, neutral),
            ("Rim softbox", (5, 3, 7), 180, 10, neutral),
            ("Curl bounce", (-3.5, -4, 2.8), 60, 6, neutral),
        ],
    }
    scenes = []
    for slug, lights in rigs.items():
        scene = baseline.copy()
        scene.name = "Trace E - " + slug
        scene.world = baseline.world.copy()
        scene.collection.children.unlink(baseline.collection.children["Studio"])
        studio = bpy.data.collections.new(slug + " lighting")
        scene.collection.children.link(studio)
        studio.objects.link(baseline.camera)
        for name, location, power, size, color in lights:
            data = bpy.data.lights.new(slug + " " + name, "AREA")
            data.energy, data.shape, data.size, data.color = power, "DISK", size, color
            obj = bpy.data.objects.new(slug + " " + name, data)
            studio.objects.link(obj)
            obj.location = location
            target = Vector((-1.6, -2.4, 0.35)) if name == "Curl bounce" else Vector((0, 0, 0))
            obj.rotation_euler = (target-obj.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = "//trace-e-" + slug + ".png"
        scene["lighting_variant"] = slug
        scenes.append(scene)
    return scenes


if __name__ == "__main__":
    baseline = build_scene()
    variants = lighting_variants(baseline)
    baseline.render.filepath = "//trace-e-neutral.png"
    selected = next(scene for scene in variants if scene["lighting_variant"] == "03-rainbow-rim")
    selected.render.filepath = "//trace-e.png"
    bpy.context.window.scene = selected
