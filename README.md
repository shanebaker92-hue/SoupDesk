# SoupDesk

Mac app: Soup Engine film stocks on any camera raw or JPEG.

- `Sources/SoupEngine/` — Soup Engine C, copied unmodified from 7DeliciousSoup `soup-7d/src/engine` (se, look, grade, stock, lut, color, wb, jpeg_dec) + `soup_bridge.c`.
- `Sources/SoupKit/` — decode (ImageIO / CIRAWFilter), grade, develop.
- `Sources/SoupDesk/` — SwiftUI app. `Resources/Stocks/` — the 27 `.fs` + INDEX.TXT.
- `Sources/soupcheck/` — verification CLI.

Build: `./build_app.sh` → `build/SoupDesk.app`, signed with the Apple Development identity (`SIGN_IDENTITY=` to override).
To share: `./build_app.sh dist` signs with Developer ID, notarizes (keychain profile `soupdesk-notary`, `NOTARY_PROFILE=` to override),
staples, and writes `build/SoupDesk.zip`. One-time setup: a Developer ID Application cert (Xcode → Settings → Accounts → Manage Certificates)
and `xcrun notarytool store-credentials soupdesk-notary --apple-id <you> --team-id A27T7KN725` with an app-specific password.

Use: drag photos/folder in. ←/→ photo, ↑/↓ stock, Return or ⌘E develop this photo, ⇧⌘E develop all.
Film stocks: F (or the star) favourites a stock and pins it to the top; favourites are stored by stock NAME in UserDefaults.
More stocks: drop or Import `.fs` files, "Get stocks" pulls any new ones from upstream `jiijii0/soup-engine/card/ML/FILM`
(GitHub API), "Make" opens the Soup Stocks web editor. User stocks live in `~/Library/Application Support/SoupDesk/Stocks`;
a stock whose NAME already exists is skipped. Unknown stocks get a generic grey roll.

Output: `<photo folder>/Soup/<name>_<stock>.jpg` (full res, q92, EXIF kept, never overwrites; `-2`, `-3`… suffix).

Check: `swift build -c release && .build/release/soupcheck photo.jpg Resources/Stocks/gold.fs`
compares the app's grading against the camera-shaped engine path (engine decoder rows straight into the look). Wrapper must be max 0.
