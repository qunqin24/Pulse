import Testing

/// The suites that read or write `PanelMetrics`, one at a time.
///
/// `PanelMetrics` is a set of process-wide globals — the panel's scale, end
/// style, figures and clock — and these suites flip them to check every
/// layout. Swift Testing runs top-level suites in parallel, so a suite marked
/// `.serialized` on its own still raced the others: one would set round ends
/// while another measured the rail, and `FreeAcrossTests` failed on a frame
/// worked out from the other suite's settings. Nested here, under one
/// serialized parent, they never overlap. A new suite that touches
/// `PanelMetrics` or measures `DockLayout` belongs here too.
@Suite("Panel layout globals", .serialized)
enum PanelGlobalsSuite {}
