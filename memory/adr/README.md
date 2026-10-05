# Architecture decision records

These ADRs capture durable implementation decisions verified against the
current code. User-facing behavior lives in
[feature memory](../../FEATURES.md); ADRs record *why* the implementation is
shaped the way it is.

| ADR | Decision |
| --- | --- |
| [0001](0001-required-tldraw-product-canvas.md) | Require the hidden-UI tldraw product canvas |
| [0002](0002-native-board-window-resizing.md) | Let native AppKit chrome own board resizing |
| [0003](0003-metal-only-isotropic-grid.md) | Render the grid only with Metal in board-view points |
| [0004](0004-single-monochrome-capture-transition.md) | Keep one Monochrome Flash capture transition |
| [0005](0005-native-first-blank-page-loading.md) | Paint blank pages natively until tldraw is ready |
| [0006](0006-unified-timed-annotations.md) | Unify timed Neo and tldraw annotations |
| [0007](0007-batched-finder-image-import.md) | Import Finder image batches into one canvas |
| [0008](0008-background-derived-color-theming.md) | Derive annotation colors from the page background |
