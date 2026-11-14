# ATROX web (P088)

Static site for universal links. Deploy the `web/` folder as-is (for example on Vercel: project root `web`, no build).

- `/.well-known/apple-app-site-association`: replace `TEAMID` with the Apple Developer Team ID. Served as `application/json`
  without redirects (see `vercel.json`).
- `/u/<username>`: friend invite. With the app installed iOS opens it directly; otherwise this page shows the invite and the
  App Store button (replace the `id0000000000` placeholder with the real App Store ID once the app exists).
- The domain must match `APP_LINK_HOST` in `ios/Config/Base.xcconfig`. The privacy policy and terms pages (P101) will live here too.
