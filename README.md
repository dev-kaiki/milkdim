# MilkDim

Ordering app and admin panel for a food distributor — customers place orders from the phone, the back office manages catalogue and orders from the browser.

Flutter · Supabase

Built by [Kaiki Quadros Ferreira](https://github.com/dev-kaiki).

> **This was a proposal that did not close.** It is a working prototype, not a
> delivered product, and it never had real users. Published because it shows the
> stack outside the industrial world I usually work in.

---

## Two apps, one backend

```
app/     ordering client — catalogue, cart, order placement, PDF receipts
admin/   back-office panel — catalogue and order management
```

Both talk to the same Supabase project. The client generates PDFs on the device
using bundled Noto Sans faces, so accented Portuguese renders correctly without
depending on whatever fonts the phone happens to have.

## Running it

Needs a Supabase project. Credentials are **not** in the source — pass them at build time:

```bash
cd app     # or: cd admin
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Both refuse to start without them rather than falling back to a default.

## Platforms

Android, iOS, macOS and web, for both apps. The iOS and macOS targets did not
exist — this was an Android-and-web prototype — and were generated with proper
bundle identifiers rather than the `com.example.*` prefix `flutter create`
leaves behind, which Apple refuses to provision at all.

The entitlement that matters is `com.apple.security.network.client`. The macOS
App Sandbox blocks outgoing connections by default and the Flutter `Release`
template declares only `app-sandbox`, so a release build launches cleanly and
then fails every Supabase call — a failure that looks like a dead backend and
is not. It is declared for both apps, in both configurations.

The ordering client also declares `com.apple.security.print`, for the PDF
receipt, and `files.user-selected.read-write` for saving it.

## Notes on this repository

The Supabase URL and anon key that were hardcoded in `main.dart` have been removed
from both apps. No customer or order data is included.

## License

MIT — see [LICENSE](LICENSE).
