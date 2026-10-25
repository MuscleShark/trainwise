# IronSage brand

The logo is IRON over SAGE in Barlow Condensed ExtraBold, both lines the same width,
standing on a loaded barbell. The SVGs here are outlines, so they display without the
font.

| File | Use |
|---|---|
| `logo.svg` | The logo on light backgrounds |
| `logo-dark.svg` | The logo on dark backgrounds |
| `app-icon.svg` | App icon, 1024 × 1024, square (iOS rounds the corners) |
| `app-icon-dark.svg` | App icon for iOS dark mode |
| `app-icon-tinted.svg` | App icon for iOS tinted mode (grayscale) |

## Colors

| Name | Light | Dark | Use |
|---|---|---|---|
| Bone | `#F4EFE6` | `#161514` | Backgrounds |
| Ink | `#111111` | `#F4EFE6` | Text and the main button |
| Plate red | `#E2412D` | `#E2412D` | The barbell plates in the logo |
| Accent | `#C8372D` | `#FF6A55` | Buttons, links and selected states in the app (passes AA on bone) |

## Regenerating

`make_logo.py` builds every SVG from the font. Barlow Condensed is under the SIL Open
Font License; download `BarlowCondensed-ExtraBold.ttf` from
[github.com/google/fonts](https://github.com/google/fonts/tree/main/ofl/barlowcondensed), then:

```bash
python3 brand/make_logo.py BarlowCondensed-ExtraBold.ttf brand
```

The app icon PNGs in `ios/IronSage/Assets.xcassets/AppIcon.appiconset` are these SVGs
rendered at 1024 × 1024 without an alpha channel (`qlmanage -t -s 1024` renders an
SVG on macOS).
