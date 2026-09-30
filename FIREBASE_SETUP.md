# Firebase setup guide (Windows and Flutter)

This guide explains the complete setup from the beginning. Once configured, signed-in customers and staff can use the app over the internet from different networks; a home Wi-Fi connection is not required.

## Current progress in this workspace

- FlutterFire configuration and the local `default` Firebase alias point to project `progressive-jewellery`.
- Email/Password Authentication, the Mumbai Firestore database, and the first admin member document have been created.
- I launched the Android emulator app: it builds and Firebase initializes. Firestore currently returns `PERMISSION_DENIED` when the app reads its member and application documents. The Firestore rules have not been deployed yet, so this is expected in Production mode. After deploying only those rules, if access is still denied, compare the signed-in account's Authentication UID with the member document ID.
- The local Firestore rules now allow a signed-in user to check only their own member document, including when it does not exist yet. This is needed for the customer approval flow; membership writes remain restricted to the backend.
- Storage and Cloud Functions have not been deployed because Firebase requested a billing upgrade. The no-billing Firestore test path is in Step 5 below.

## Before you start

You need:

- A Google account to own the Firebase project.
- Flutter installed and working on this computer.
- Node.js 22 installed (the app's Cloud Functions use Node 22).
- An Android phone or emulator for the first run.

The app uses Cloud Firestore for shared data, Firebase Authentication for sign-in, Cloud Storage for images, and Cloud Functions for secure account approvals and order processing. Current Firebase requirements mean Cloud Storage and Cloud Functions need the pay-as-you-go **Blaze** plan. Review Firebase pricing and add a billing account before enabling/deploying those services; actual use can incur charges. See the official [Cloud Storage Flutter setup](https://firebase.google.com/docs/storage/flutter/start) and [Cloud Functions setup](https://firebase.google.com/docs/functions).

## 1. Create your Firebase project

1. Open the [Firebase Console](https://console.firebase.google.com/) and sign in with the Google account that will own the app's backend.
2. Select **Add project** and follow the prompts. You can skip Google Analytics for this app setup.
3. Open the project settings and copy the **Project ID**. This is the short ID, not the project display name. Keep it for the commands below.
4. Upgrade the project to the **Blaze** plan and attach a billing account before setting up Storage and deploying Functions.

Firebase serves users around the world; the selected database region is where the database is hosted. This project's Functions are configured for `asia-south1` (Mumbai), so if most of your users are in India, choose `asia-south1` for Firestore to keep the database near the backend. Choose the region closest to most of your users if they are elsewhere. Pick carefully because the Firestore database location cannot be changed after creation. See [Firestore locations](https://firebase.google.com/docs/firestore/locations).

## 2. Install and sign in to the Firebase command-line tools

Open **PowerShell** and install Firebase CLI. If `node` is not recognized, install Node.js 22 first, then close and reopen PowerShell.

```powershell
node --version
npm --version
npm install -g firebase-tools
firebase --version
firebase login
firebase projects:list
```

In the browser, sign in with the same Google account. `projects:list` should show the project you created. The Firebase CLI requires Node.js; see the official [Firebase CLI guide](https://firebase.google.com/docs/cli).

## 3. Connect this Flutter app to the Firebase project

In PowerShell, go to the project folder and generate the app configuration. Replace the example project ID with yours:

```powershell
cd D:\progressive_jewellery
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID
```

For the first setup, select **Android**. Select iOS or other platforms only if you plan to build for them. The Android application ID for this project is `com.example.progressive_jewellery`; the iOS bundle ID, if used, is `com.example.progressiveJewellery`. Accept the CLI's prompts to register the app. It will generate `lib/firebase_options.dart` and the platform configuration files. Keep those generated files in the project. The Flutter app initializes Firebase using this generated configuration. More details are in [Firebase setup for Flutter](https://firebase.google.com/docs/flutter/setup).

This workspace has already completed this step for project `progressive-jewellery`; do not rerun it unless connecting to a different Firebase project or adding a platform.

If PowerShell says `flutterfire` is not recognized after activation, close and reopen PowerShell. If it still is not recognized, add Dart's global executable folder to your Windows PATH. It is usually `%LOCALAPPDATA%\Pub\Cache\bin`.

## 4. Turn on sign-in and create the database

In Firebase Console, open your project:

1. Go to **Authentication** → **Get started** → **Sign-in method**. Enable **Email/Password** and save. This is the sign-in method used by the app. See [Firebase email/password authentication](https://firebase.google.com/docs/auth/flutter/password-auth).
2. Go to **Firestore Database** (sometimes shown under **Build** or **Databases & Storage**) → **Create database**.
3. Choose **Production mode**, then choose the region from Step 1 (recommended here: `asia-south1` for an India-based user base).
4. Wait until the database has finished creating.
5. Go to **Storage** → **Get started** and create the default bucket. Choose a region near your users, ideally the same region as Firestore. Storage now requires the Blaze plan. Do not make the bucket publicly accessible.

Production mode initially blocks app access. The next step deploys this repository's rules, which define which signed-in users can read or change each kind of data. Do not leave a database in open test mode.

## 5. Select the project and deploy this app's backend and rules

In PowerShell, from the project root, select the same Firebase project and deploy the supplied rules and Functions:

```powershell
cd D:\progressive_jewellery
firebase use --add
firebase deploy --only firestore:rules,storage,functions
```

For `firebase use --add`, choose your project from the list and give it an alias such as `default`. The deploy command publishes `firestore.rules`, `storage.rules`, and the callable Cloud Functions in `functions/`. Functions are deployed to `asia-south1`. Deployment requires Blaze; review [Cloud Functions requirements](https://firebase.google.com/docs/functions) if the CLI reports a billing or API setup error.

**To test Authentication and Firestore without enabling billing**, do not use the combined deploy command while Storage has not been initialized. From the project root, deploy only the Firestore rules:

```powershell
firebase deploy --only firestore:rules
```

Then restart the app and sign in again. The admin member document should be readable under these rules. Customer account approval and order processing still need the Cloud Functions, and product photo uploads need Storage; those features will remain unavailable until those services are set up.

This publishes only the repository's Firestore rules. Firebase CLI rule deployment replaces the rules currently in the Firebase Console, so check that the local `firestore.rules` is the version you want to use before running it. See the [Firebase CLI deployment reference](https://firebase.google.com/docs/cli).

## 6. Create the first admin account

The rules do not let a new user grant themselves admin access. Bootstrap one trusted admin in the console:

1. In Firebase Console, open **Authentication** → **Users**. If you already created your account in the app, find that existing email in the list and use it; do not create a second user with the same email. Otherwise choose **Add user**, enter the admin's email and a password, and create the user.
2. Copy that user's **UID** from the Authentication user list. If you registered in the app, this is the same account that currently shows the access request screen.
3. Open **Firestore Database** → **Data**. Create this document path by making the collections/documents in order:
   - Collection `stores`
   - Document `progressive-jewellery`
   - If the console asks for a field on this parent document, add `name` with value `Progressive Jewellery` (string).
   - Subcollection `members`
   - Document ID: the copied Authentication UID
4. Add these fields with the indicated Firestore types. Replace the example values with the admin's real UID and email:

   | Field | Value | Type |
   | --- | --- | --- |
   | `uid` | Same UID as the document ID | string |
   | `id` | `ADM-001` | string |
   | `name` | `Store administrator` (or the admin's name) | string |
   | `email` | Admin's email | string |
   | `login` | Admin's email | string |
   | `role` | `admin` | string |
   | `canShop` | `true` | boolean |
   | `canManageStock` | `true` | boolean |
   | `canCreateBills` | `true` | boolean |
   | `createdAt` | Current time | timestamp |

5. Sign in to the app with that same email and password (or sign out and sign back in if already signed in). This makes that account the first admin. The admin can then review customer applications and approve accounts in **People & permissions**. There is no pre-created admin account; the project owner bootstraps the first one this way.

Customers can sign up in the app, but they do not get access to store data until an admin approves their application. Do not create a member document manually for each customer; approvals are handled by the backend.

## 7. Run the app and check it

Connect an Android phone with internet access or start an emulator. From the project folder, run:

```powershell
flutter pub get
flutter run
```

Sign in as the admin and confirm the app opens. Then create a customer account and approve it from **People & permissions**. Sign in as that customer on another device or network to check shared products and orders. A pull-down refresh fetches current server data and keeps items already in the bag.

## If something does not work

- **The app says Firebase is not configured:** rerun `flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID` from `D:\progressive_jewellery` and check that `lib/firebase_options.dart` no longer contains empty placeholder values.
- **Creating an account says the Firebase function was not found:** from `D:\progressive_jewellery`, confirm `firebase use` selects the same project ID shown in `lib/firebase_options.dart`, then run `firebase deploy --only functions`. The deployed Functions should include `submitStoreAccountApplication` in `asia-south1`. Firebase Authentication may already have created the user. If that user is you, the first admin, use its existing UID to bootstrap your admin account as described in Step 6. For a customer, deploy the function, then sign in with the existing account and retry **Request approval**.
- **Permission denied after sign-in:** confirm the first admin's document is at `stores/progressive-jewellery/members/<that user's Auth UID>` and has the exact field types above. Confirm rules deployed successfully.
- **Deploy says billing is required:** confirm the Firebase project is on Blaze and has an active billing account, then retry the deploy command.
- **`firebase` or `flutterfire` is not recognized:** reopen PowerShell after installation. Check Firebase CLI with `firebase --version`; for FlutterFire, check the Dart global executable folder is on PATH.
- **The app cannot connect on another network:** confirm that device has internet, that it is running a build configured for this same Firebase project, and that the project deployment succeeded.

Push notifications are optional for the initial setup. They need extra device configuration, especially an APNs key for iOS. The app's shared Firestore data and account approval do not depend on push notifications.
