# Smart Telescope Sort

Free macOS app that copies TIFF and FITS files from a smart-telescope download folder into `Targets {year}/{object}`.

Independent app. Not affiliated with or created by telescope manufacturers. Model names in the source identify folder layouts only. A modified build should keep the product name free of those trademarks.

The Mac App Store edition is signed and distributed separately. A build from this repository is your own local copy.

## Build

Requires Xcode command-line tools.

```bash
cd App
chmod +x build-app.sh
./build-app.sh
```

The app is written next to the `App` folder as `Smart Telescope Sort.app`. The script compiles for the Mac you are on and ad-hoc signs it. You do not need an Apple Developer certificate to run your own changes.

Rebuild the bundled manual with:

```bash
python3 App/Scripts/build-user-manual.py
```

That script needs `reportlab`.

## Try it

`Demo Captures/` holds placeholder files, not real images. In the app, set Source Captures to one brand folder, such as `Demo Captures/Seestar`, then press Review file plan.

| Folder | Layout |
|--------|--------|
| `Vaonis/` | Dated session folders |
| `Seestar/` | Object album folders |
| `DWARF/` | Session folders |
| `Origin/` | Object and date folders |

The app reads `.tif`, `.tiff`, `.fit`, and `.fits`. It leaves JPG and PNG alone.

## License

MIT. See [LICENSE](LICENSE).
