# Progressive Jewellery

A Flutter storefront and stockroom prototype for Android, iOS, Windows, and macOS.

## Included

- Sign in with an email address or phone number and password.
- Admin-created Admin, Owner, Employee, and Customer accounts with generated account IDs and configurable shop, inventory, and billing permissions. A maximum of two admin accounts is enforced in the app.
- Product inventory with product ID, name, quality, category, description, photo, stock counted in pieces, and a price per piece.
- Add product photos from a device gallery or file, or use an image URL. Create categories while adding a product.
- A per-account bag with quantity controls, stock checks, and order placement.
- Separate customer order history, staff order inbox, and customer-grouped requests for out-of-stock items. Unavailable pieces are kept pending and are not included in bills.
- Itemized bills and downloadable PDF receipts with the Progressive Jewellery wordmark, customer details, product IDs, quality, piece counts, per-piece prices, totals, payments, and balance due.
- Cash and credit billing, customer balances, payment history, and partial payment recording for Owners and Admins.
- Daily business totals and a rolling seven-day sales chart.
- Business profile and personal account settings.

## Demo sign-in

- Email: `admin@progressivejewellery.com`
- Password: `admin123`

## Prototype data and notifications

This version keeps accounts, products, selected photo bytes, bags, orders, bills, and payments in app memory. Data is separate by customer account within the running app, but resets when the app closes and does not sync between devices. Staff order alerts appear in the in-app inbox; push notifications and shared live updates require a configured backend. Connect a backend before using real customer accounts or business data.

## Run

Install Flutter, then run `flutter run` for a connected device or desktop target. See the [Flutter setup guide](https://docs.flutter.dev/get-started/install) for platform-specific requirements.
