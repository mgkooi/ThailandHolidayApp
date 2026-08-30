# Reizz color theme

`ReizzColors` is the central semantic color source. Views use semantic names instead of parsing or embedding
brand hex values.

| Semantic color | Light | Dark |
| --- | --- | --- |
| `primaryDark` | `#003049` | `#003049` |
| `primaryLight` | `#669BBC` | `#669BBC` |
| `accent` | `#FB8B24` | `#FB8B24` |
| `background` | white | black |
| `brandForeground` | `#003049` | `#669BBC` |
| `primaryText` | `#003049` | system label |
| `secondaryText` | system secondary label | system secondary label |
| `surface` / `cardBackground` | light neutral gray | dark neutral surface |
| `divider` | system separator | system separator |

The orange accent is reserved for selected tab state and deliberate actions. Brand foreground switches to the
lighter blue in dark mode for contrast. Body text uses system label colors where brand colors would reduce
readability.

The former `travelTeal`, `travelOrange`, and `travelBackground` aliases remain temporarily for source
compatibility and now resolve through the semantic theme. Other legacy category colors remain centralized in
`TodayComponents.swift` pending a later cross-tab migration.
