# ATROX web (P088)

Static site for universal links. Deploy the `web/` folder as-is (for example on Vercel: project root `web`, no build).

- `/.well-known/apple-app-site-association`: `TEAMID` is replaced by the Team ID (5222NFFPX7). Served as `application/json`
  without redirects (see `vercel.json`).
- `/u/<username>`: friend invite. With the app installed iOS opens it directly; otherwise this page shows the invite and the
  App Store button (replace the `id0000000000` placeholder with the real App Store ID once the app exists).
- The domain must match `APP_LINK_HOST` in `ios/Config/Base.xcconfig`. - `/privacy`, `/terms`, `/support` (P101): bilingual (EN + TR on one page) **drafts**; the `[…]` fields (controller, contact, dates, regions, retention) and a lawyer's review are required before publishing (`docs/HUKUK-TASLAKLARI.md`). Point `LEGAL_PRIVACY_URL` / `LEGAL_TERMS_URL` in `ios/Config/*.xcconfig` at them.
