# Progressive Jewellery

A Flutter storefront and stockroom app for Android, iOS, Windows, and macOS. Firebase Authentication and Cloud Firestore provide shared online accounts and business data across devices connected to the internet.

## Included

- Email and password sign-in, admin-created team accounts, and customer account requests that require admin approval.
- Product inventory with product ID, name, quality, category, description, photo, piece count, and per-piece price.
- A per-account bag with quantity controls, stock checks, and online order placement.
- Customer order history, staff order inbox, and requests for out-of-stock items.
- Itemized bills, downloadable PDF receipts, cash and credit billing, balances, and payment history.
- Daily business totals, a rolling seven-day sales chart, and business and account settings.
- Pull-to-refresh from the online database without clearing the bag.

## Connect Firebase

This repository does not include a Firebase project configuration. Run the steps in [FIREBASE_SETUP.md](FIREBASE_SETUP.md) to attach a Firebase project and deploy its security rules and Cloud Functions. The app now shows a setup message if the cloud configuration is missing; it does not silently use local demo records for store data.

## Run

Install Flutter, connect Firebase as described above, then run `flutter run` for a configured target. See the [Flutter setup guide](https://docs.flutter.dev/get-started/install) for platform requirements.

## App icon

The launcher icon design is in `tools/generate_app_icons.py`. Change its initials, colors, or drawing there, then run `python tools/generate_app_icons.py` to regenerate the SVG source and Android, iOS, macOS, Windows, and web icons. The generator requires Pillow (`python -m pip install pillow`).
