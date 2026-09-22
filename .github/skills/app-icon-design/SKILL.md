---
name: app-icon-design
description: Design, draw, refine, or critique distinctive macOS and iOS app icons. Use for app-icon concepts, illustrated or skeuomorphic icons, geometric marks, mascots, icon families, small-size readability, and Icon Composer delivery. Applies lessons from an extensive visual icon study without copying the reference artwork.
---

# App icon design

Make a small, recognizable object with a point of view, not a miniature landing
page. The icon should be identifiable before its surface detail becomes visible.
Excellent execution can be flat, dimensional, playful, restrained, or richly
illustrated; the brief determines which.

Read [the study findings](references/study-findings.md) before designing.
Read [Apple delivery](references/apple-delivery.md) before preparing platform
assets. These references are self-contained; the private photographic library
is useful evidence, not a required dependency.

## Establish the brief

Use the user's supplied context before asking anything. Resolve material
ambiguity about the app's function, existing identity, target platforms,
deployment versions, and expected deliverable. A concept preview, editable
artwork, and an integrated production icon are different outcomes.

Write a short working brief:

- **Promise:** the one useful thing the app does, in ordinary language.
- **Recognition:** the object, gesture, creature, or shape someone should recall.
- **Personality:** two specific qualities, such as precise and tactile.
- **Signature:** the feature that makes this design distinguishable from peers.
- **Constraints:** existing marks, forbidden associations, platform targets,
  appearances, and output formats.

Do not invent product facts. For a refinement, retain the existing identity
unless the user requested a replacement.

## Design the idea before the finish

For a new identity, explore three genuinely different constructions, not three
colors of the same glyph. For a constrained refinement, compare the incumbent
with only the relevant alternatives.

| Construction | Good reason to choose it | Typical failure |
|---|---|---|
| Literal tool or object | A distinctive functional object explains the app | A tiny photorealistic object with no readable silhouette |
| Integrated metaphor | Two meanings can share one contour or structural part | Two unrelated symbols pasted together |
| Mascot | Expression and personality are part of the product | A generic face differentiated only by costume |
| Geometric mark | An ownable relationship of shapes carries the idea | A stock glyph centered on a fashionable gradient |
| Miniature scene | Place or atmosphere is essential to the promise | A poster whose protagonist disappears at small size |
| Letter or numeral | The character is itself recognizable and distinctive | Default-font initials pretending to be an identity |

Draw the candidates as simple silhouettes or broad value masses first. Show
them at small size, not only as enlarged mockups. Keep the strongest idea by
recognition and distinctiveness, not by how expensive its shading looks.

Avoid borrowing the reference's recognizable mascot, logo, distinctive
composition, or exact color arrangement. Transfer the principle.

## Construct the selected icon

1. **Block the masses.** Establish the tile, dominant subject, one supporting
   cue, and negative space. Try a silhouette and a three-value rendering before
   texture. Start from the current platform template; do not prescribe one
   universal corner radius or arbitrary percentage safe area.
2. **Make the signature explicit.** Name the defining cutout, proportion, fold,
   eye spacing, asymmetric accent, or gesture. Enlarge it until it survives
   reduction. If it vanishes, simplify its neighbors rather than adding detail.
3. **Balance optically.** Compare against adjacent icons at the same displayed
   size. A thin diagonal object, dense cube, and round face need different
   internal scales. Center perceived weight, not just the bounding box.
4. **Separate by value.** Give the identifying boundary the clearest contrast.
   Use color to support that hierarchy. Check grayscale before increasing
   saturation.
5. **Choose a coherent rendering system.** Keep perspective, light direction,
   edge softness, and material response consistent. Use broad shading to
   explain form; subordinate grain, engraving, stitches, and tiny controls.
6. **Make the platform layers intentional.** Separate pieces that need different
   depth or appearance behavior. Do not turn every decorative contour into a
   separate layer. Follow the live Icon Composer requirements.

### Rendering discipline

For **flat artwork**, tune contours, joins, optical spacing, and figure-ground
relationships. Flatness does not excuse a generic silhouette.

For **illustrated objects**, exaggerate the diagnostic feature: the lens, handle,
page fold, cap, or opening. One broad reflection can explain curvature better
than many little glints. Put contact shadows where surfaces meet; avoid an
unmotivated halo around every piece.

For **mascots**, define head contour, eye spacing, mouth shape, and one signature
feature before adding clothing. Test whether the expression survives a
single-color or very small rendering.

For **geometric marks**, make the empty center, gap, and intersection deliberate.
Remove accidental tangencies and almost-parallel edges.

For **scenes**, use a few depth bands and one protagonist. Remove scenery before
shrinking the subject.

For **families or alternate icons**, record the invariant and the permitted
variation. Expression, pose, costume, finish, and background can vary; changing
all identifying relationships at once produces a different identity.

## Draw with appropriate tools

Use tools that actually exist in the environment. Prefer editable vector paths
for controlled geometry, letters, silhouettes, and flat layers. Convert type
to outlines when exporting SVG. Use layered raster or 3D tools for material
illustration when the available workflow supports them.

Image generation can explore an original concept when an appropriate tool is
available and permitted, but an attractive generated PNG is not automatically
editable, correctly layered, licensed reference material, or production-ready.
Do not claim to have created a native `.icon`, `.icns`, or asset catalog without
producing and checking the real artifact.

If a required authoring or export tool is unavailable, state the limitation and
deliver the usable editable layers and preview rather than fabricating a
platform file. Do not replace the requested rich illustration with unrelated
primitive shapes merely because those are easy to generate.

## Review at the size people use

Make a single comparison sheet containing:

- A large construction view and genuine 16, 32, 64, and 128 px raster previews.
  These are design stress tests, not a substitute for the platform's export
  sizes. Display the small previews at 1:1, not enlarged.
- A solid silhouette and grayscale version.
- The actual platform mask, light and dark surroundings, and a small
  neighboring-icon comparison.
- Supported appearance variants in Icon Composer when native delivery is in
  scope. Without that check, label appearance behavior unverified.

Check the dominant contour, diagnostic gap, facial expression, optical size,
and foreground separation in one pass. A design need not retain every detail
at 16 px, but it must not collapse into an unrelated shape.

Use this **editorial rubric**, not as a claimed Apple standard:

| Criterion | Weight | Evidence |
|---|---:|---|
| Recognition | 25 | Subject or gesture reads without its name |
| Distinctiveness | 25 | One ownable signature remains among nearby icons |
| Small-size structure | 20 | Focal masses and essential gaps survive reduction |
| Platform behavior | 15 | Mask, appearances, and integration have been checked |
| Craft | 15 | Curves, spacing, perspective, light, and materials are coherent |

Scores are judgments, not measurements. Explain the weakest criterion with
visible evidence; do not award points for checks that were not performed.
Unlicensed copying, broken exports, missing requested variants, or an unreadable
essential mark are release blockers regardless of score.

Fix the identified weaknesses in one coherent pass, then confirm the fixes.
Do not keep polishing an attractive large image while its small version fails.

## Deliver

For a concept request, supply the actual preview, concise rationale, and the
selected signature. For an artwork request, include the editable source,
organized layers, and comparison sheet. For production integration, also supply
the real platform artifact and report any unverified target or appearance.

Use meaningful layer names such as `01-body`, `02-face`, and `03-signature`.
Keep original source artwork separate from export files.

For reference-analysis work, retain provenance, native crop dimensions,
timestamps, and uncertainty. Uniform comparison canvases do not recover detail
from low-resolution references. For photographed square tiles, correct the
projected quadrilateral before normalizing size: fit straight side segments,
ignore the rounded corners, and map their intersections to a square. A square
output canvas or a stretched bounding box is not perspective correction.
Keep the untouched crop and distinguish measured edges from estimated corners.
Flag clipped or ambiguous boundaries rather than manufacturing a complete tile;
do not flatten intentional perspective inside the artwork.
Do not treat photographed colors as exact
design tokens or an illustrated book's historical exports as current platform
requirements.
