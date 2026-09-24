# Firebase setup for Android and iOS

The app code is connected to Firebase Auth, Firestore, Storage, Cloud Functions, and FCM. This repository does not contain a Firebase project configuration, so the app stays in its local demo mode until a project is attached.

## Attach the Firebase project

1. Create or choose a Firebase project and register these application IDs:
   - Android: `com.example.progressive_jewellery`
   - iOS: `com.example.progressiveJewellery`
2. From the repository root, install and run the FlutterFire CLI:

   ```sh
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<your-firebase-project-id>
   ```

   Select Android and iOS. The CLI generates the native Firebase configuration and applies the Android Gradle plugin setup. Keep the generated files in the project.
3. In Firebase Console, enable **Authentication → Email/Password**, create a **Cloud Firestore** database, and enable **Storage**.
4. Link the local Firebase CLI project and deploy the security rules and backend:

   ```sh
   firebase use --add
   firebase deploy --only firestore:rules,storage,functions
   ```

   Cloud Functions deployment requires the Firebase **Blaze** plan. Function usage is billed based on Google Cloud usage; review Firebase’s [Cloud Functions billing and deployment requirements](https://firebase.google.com/docs/functions) before deployment.

## Create the first store admin

The first admin must be created once in Firebase Console because account creation in the app is restricted to an existing admin:

1. Create the admin’s email/password user in **Authentication** and copy the user UID.
2. In Firestore, create `stores/progressive-jewellery/members/<AUTH_UID>` with these fields:

   ```text
   uid: <AUTH_UID>                  (string)
   id: ADM-001                     (string)
   name: Store administrator       (string)
   email: <admin email>            (string)
   login: <admin email>            (string)
   role: admin                      (string)
   canShop: true                    (boolean)
   canManageStock: true             (boolean)
   canCreateBills: true             (boolean)
   createdAt: <timestamp>
   ```

   Sign in with that same email and password in the app. The admin can then create customer and staff accounts from **People & permissions**. Passwords are managed by Firebase Authentication and are never written to Firestore.

## Turn on order notifications

The app registers each signed-in account's device for FCM. When a customer places an order, the backend notifies store staff with the customer and order details. When an admin, owner, or permitted employee places an order for a customer, the backend sends the customer a confirmation naming the staff member who placed it.

- On iOS, upload an APNs authentication key to the Firebase project’s Cloud Messaging settings and use a provisioning profile with Push Notifications enabled. Push capability and remote notification background modes are already present in the Xcode project.
- On Android 13 and newer, staff must allow notifications when prompted. Notifications also require Google Play services on the device.

Firebase’s [Flutter messaging setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) documents the APNs key, iOS capabilities, and token requirements.

The Firestore listeners update products, stock, categories, carts, orders, bills, saved walk-in customers, production tasks, pending requests, and business settings across signed-in devices. Order placement and stock decrement run in one server transaction. Walk-in sales are recorded against a saved customer record, and the assigned worker receives a push notification with the product, current stock, and requested quantity.

The app keeps a local backup of demo-mode users, customers, products, carts, bills, orders, and settings on that device. Cross-device sync requires the Firebase project setup above and deployment of the current Firestore rules and Cloud Functions; local demo data does not sync between devices.
