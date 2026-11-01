# Be Vietnam Pro (bundled font, T20)

Static TTF files copied unmodified from the Google Fonts repository. Spec: `docs/specs/T20.md` §4.5.

- Source: https://github.com/google/fonts/tree/6c1dbe27dcf7d817d4b62cec033ba77fa8e2a5ec/ofl/bevietnampro
- `google/fonts` commit (tip of `main` at download time, 2026-11-01): `6c1dbe27dcf7d817d4b62cec033ba77fa8e2a5ec`
- Last commit touching `ofl/bevietnampro` at that point: `c13390277dfb1fcc7415d84ef7ef9cfc1e52f8c1` (2026-03-03)
- Download URL pattern: `https://raw.githubusercontent.com/google/fonts/<commit>/ofl/bevietnampro/<file>`

| File | Weight | Size (bytes) | SHA-256 |
|---|---|---|---|
| `BeVietnamPro-Regular.ttf` | 400 | 132948 | `cd1ef6e9d7db28ad5cdb88a65ccbe693870e60d340b791f349d248342b4fe4c3` |
| `BeVietnamPro-Medium.ttf` | 500 | 135980 | `b60832bfa0fcd015158112c64d7e3fdad3b0c6287d1823f85a3103636e845268` |
| `BeVietnamPro-SemiBold.ttf` | 600 | 136736 | `bd8e27eb02720b9d91e59e4f10a90878643219f25ce6a8d9a4f06a8a88d3bb71` |
| `BeVietnamPro-Bold.ttf` | 700 | 140300 | `7f738fe5c43c8872807b20e2d30d42163618de8a4daf7f48a939adac32c16847` |
| `OFL.txt` | - | 4397 | `6b7f8f73609a25ea78c891e34cf37b06f8a676b7ea986e941e43b009110f2a85` |

Total font size: 545964 bytes (about 533 KiB).

## License

SIL Open Font License 1.1, "Copyright 2021 The Be Vietnam Pro Project Authors
(https://github.com/bettergui/BeVietnamPro)", no Reserved Font Name. Designers (METADATA.pb): Lâm Bảo, Tony Le,
ViệtAnh Nguyễn.

`OFL.txt` is declared as an asset and registered in `LicenseRegistry` by `registerFontLicenses()`
(`lib/core/design/fonts/font_licenses.dart`), so the notice ships with the app. Do not modify the font files; do not sell
them on their own.

The fonts have no `tnum` OpenType feature, so `FontFeature.tabularFigures()` in `NapBigValue` has no effect (harmless).

## Updating

Pick a new `google/fonts` commit, download the same 4 files + `OFL.txt` from that commit, and update the table above
(`sha256sum`, `wc -c`).
