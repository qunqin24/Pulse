# UI

The panel is SwiftUI inside a transparent, non-activating AppKit `NSPanel`. AppKit owns size, placement, and real mouse input.

| Doc | Owns |
|---|---|
| [panel-geometry.md](panel-geometry.md) | Frame, overlay vs stack, dock/float, top edge, scale |
| [input.md](input.md) | Hover, drag, ring click, hit testing |
| [rings-and-surface.md](rings-and-surface.md) | Glass, colours, activity mark, halo, countdown |
| [settings.md](settings.md) | Settings window chrome and copy |

Why the frame never grows with a card, why `.onHover` is banned, and why glass drag is not “verified”: [../decisions/README.md](../decisions/README.md).
