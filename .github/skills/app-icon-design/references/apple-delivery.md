# macOS and iOS delivery

**Documentation checked: 2026-09-22.** Recheck against the actual Xcode release,
deployment targets, and current Apple templates before shipping. Historical
book samples are not authoritative export specifications.

## Primary sources

- [App icons, Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Icon Composer](https://developer.apple.com/icon-composer/)
- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)

The concrete workflow below was verified against Apple's Icon Composer
documentation, including its machine-readable documentation content. The HIG
and Design Resources links are the places to refresh visual guidance and
templates.

## First choose the real delivery route

Inspect the project, supported releases, and existing icon integration before
changing anything. Do not migrate an established asset catalog to Icon Composer
merely because the new tool exists.

| Route | Appropriate output |
|---|---|
| Concept exploration | Clearly labeled preview and editable source |
| Current layered icon | Real Icon Composer file, source layers, appearance checks |
| Existing asset-catalog workflow | Correct assets and catalog configuration for the actual targets |
| Legacy macOS workflow | Valid `.icns` or the project's existing catalog output, generated with supported tools |

Apple documents an important migration consequence: adding an Icon Composer
file replaces the existing icon asset catalog for the app icon. Xcode generates
similar-looking fallback icons for earlier releases. To retain the existing
icon on those releases, continue using the asset-catalog route rather than
assuming both approaches coexist unchanged.

Do not claim a PNG renamed to `.icon` or `.icns` is a valid native artifact.

## Prepare layered artwork

- Start from the latest Apple template. Apple's checked documentation gives
  1024 x 1024 px as the canvas for iPhone, iPad, and Mac.
- Keep the full canvas coordinates consistent across imported layers.
- Separate graphics that need independent depth, platform, or appearance
  settings. Give layers meaningful names with back-to-front ordering.
- Prefer SVG for supported vector artwork. Convert text to outlines. Use PNG
  for raster artwork or unsupported SVG features.
- Do not export the canvas mask; the system supplies it.
- Prepare clean layers rather than baking in the background color/gradient,
  blur, shadows, specular effects, opacity, or translucency that will be
  adjusted in Icon Composer.
- Organize the imported artwork into at most four groups, as directed by the
  checked documentation. Groups become the depth layers rendered by the
  platform; a group may contain multiple source graphics.

Do not confuse deliberate illustrated form shading with an outer system
shadow. If a rendered illustration already contains a material treatment,
preview it carefully and avoid applying a second conflicting treatment.
Icon Composer supports disabling Liquid Glass effects for an individual layer.
The correct choice is target- and artwork-dependent, not "make every layer
glossy."

## Preview the variants that actually ship

The checked documentation provides **default**, **dark**, and **mono**
appearances for iOS and macOS. Mono options include light/dark and clear/tinted
variants. Inspect these in the real authoring tool rather than approximating
all of them with a single grayscale filter.

Check:

- iOS and macOS separately, including optical scale and the actual mask.
- Dark and light backgrounds, plus at least one busy background.
- Mono, clear, and tinted behavior where supported.
- Small platform preview sizes as well as the large artwork.
- Whether translucent overlaps, thin gaps, or eye openings lose contrast.
- Whether the system's lighting conflicts with any pre-rendered material.
- The fallback appearance generated for supported earlier releases.

The live documentation describes controls for comparing rendering generations,
including 26 and 27, and notes that some settings do not have the same effect
on earlier systems. Use the versions actually available in the installed
toolchain; do not assert that a newer effect was verified on an older OS.

## Integrate without collateral changes

Use the project's established target configuration, naming, and export process.
Keep the editable source separate from generated assets. Do not replace menu-bar
template images, document icons, badges, or toolbar glyphs when the request is
only for the application icon.

For macOS, inspect the icon in the Dock and small Finder contexts when possible.
For iOS, inspect its actual home-screen size and supported appearance changes.
The skill's 16/32/64/128 px stress sheet supplements these checks; it is not an
Apple asset-size manifest.

A native export is complete only after the real file opens or builds through
the relevant supported workflow and the requested integration is checked.
Follow the user's permission requirements before launching a project build.
If native preview or integration cannot be run, deliver the artwork and name
the remaining check explicitly.
