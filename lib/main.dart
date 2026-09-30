import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:progressive_jewellery/services/firebase_app_service.dart';
import 'package:progressive_jewellery/services/order_notification_service.dart';
import 'package:progressive_jewellery/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (error) {
    firebaseError = error.toString();
    debugPrint('Firebase could not start: $error');
  }
  try {
    await OrderNotificationService.initialize();
  } catch (error) {
    debugPrint('Order notifications are unavailable: $error');
  }
  final store = AppStore(firebaseEnabled: firebaseReady, seedDemoData: false);
  runApp(
    ProgressiveJewelleryApp(
      firebaseReady: firebaseReady,
      firebaseError: firebaseError,
      store: store,
    ),
  );
}

const _ink = Color(0xFF242321);
const _muted = Color(0xFF77736C);
const _paper = Color(0xFFFAF8F3);
const _gold = Color(0xFFB08A48);
const _line = Color(0xFFEAE5DA);

DateTime _storedDate(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => DateTime.now(),
};

double _storedDouble(Object? value) => value is num ? value.toDouble() : 0;

int _storedInt(Object? value) => value is num ? value.toInt() : 0;

String _accountRequestError(
  FirebaseFunctionsException error, {
  required String fallback,
}) {
  if (error.code == 'not-found') {
    return 'The Firebase account-request function was not found. Check that this app is connected to the right Firebase project, then run `firebase deploy --only functions` from the project folder.';
  }
  return error.message ?? fallback;
}

class ProgressiveJewelleryApp extends StatefulWidget {
  const ProgressiveJewelleryApp({
    super.key,
    this.firebaseReady = false,
    this.firebaseError,
    this.localAccountId,
    this.store,
  });

  final bool firebaseReady;
  final String? firebaseError;
  final String? localAccountId;
  final AppStore? store;

  @override
  State<ProgressiveJewelleryApp> createState() =>
      _ProgressiveJewelleryAppState();
}

class _ProgressiveJewelleryAppState extends State<ProgressiveJewelleryApp> {
  late final _store =
      widget.store ??
      AppStore(
        firebaseEnabled: widget.firebaseReady,
        seedDemoData: !widget.firebaseReady && widget.firebaseError == null,
      );
  Account? _signedIn;

  @override
  void initState() {
    super.initState();
    final localAccountId = widget.localAccountId;
    if (!widget.firebaseReady && localAccountId != null) {
      for (final account in _store.accounts) {
        if (account.id == localAccountId) {
          _signedIn = account;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Progressive Jewellery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _gold,
          primary: _ink,
          secondary: _gold,
          surface: Colors.white,
        ),
        fontFamily: 'Georgia',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'Arial', color: _ink),
          bodySmall: TextStyle(fontFamily: 'Arial', color: _muted),
          labelLarge: TextStyle(
            fontFamily: 'Arial',
            fontWeight: FontWeight.w600,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F6F1),
          hintStyle: const TextStyle(color: _muted, fontFamily: 'Arial'),
          labelStyle: const TextStyle(color: _muted, fontFamily: 'Arial'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _gold, width: 1.5),
          ),
        ),
      ),
      home: widget.firebaseReady
          ? _FirebaseAuthGate(store: _store)
          : widget.firebaseError != null
          ? _FirebaseSetupRequired(error: widget.firebaseError!)
          : _signedIn == null
          ? LoginPage(store: _store, onLogin: _localLogin)
          : ShopShell(
              key: ValueKey(_signedIn!.id),
              store: _store,
              account: _signedIn!,
              onLogout: _localLogout,
            ),
    );
  }

  void _localLogin(Account account) {
    setState(() => _signedIn = account);
    SharedPreferences.getInstance().then(
      (preferences) => preferences.setString('local_account_id', account.id),
    );
  }

  void _localLogout() {
    setState(() => _signedIn = null);
    SharedPreferences.getInstance().then(
      (preferences) => preferences.remove('local_account_id'),
    );
  }
}

class _FirebaseSetupRequired extends StatelessWidget {
  const _FirebaseSetupRequired({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48, color: _gold),
                const SizedBox(height: 18),
                const Text(
                  'Connect the shared store database',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 25),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This app needs its Firebase project configuration to sign in and sync orders, customers, products, and bags over the internet. Local demo data is disabled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Arial', height: 1.5),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Run the Firebase setup steps in FIREBASE_SETUP.md, then restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FirebaseAuthGate extends StatelessWidget {
  const _FirebaseAuthGate({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: FirebaseAppService.auth.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) {
        return LoginPage(
          store: store,
          onLogin: (_) {},
          firebaseAuthEnabled: true,
        );
      }
      return _FirebaseMemberGate(
        key: ValueKey(user.uid),
        userId: user.uid,
        store: store,
      );
    },
  );
}

class _FirebaseMemberGate extends StatefulWidget {
  const _FirebaseMemberGate({
    super.key,
    required this.userId,
    required this.store,
  });

  final String userId;
  final AppStore store;

  @override
  State<_FirebaseMemberGate> createState() => _FirebaseMemberGateState();
}

class _FirebaseMemberGateState extends State<_FirebaseMemberGate> {
  bool _notificationsStarted = false;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseAppService.memberDocument(widget.userId).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final data = snapshot.data?.data();
      if (snapshot.hasError || data == null) {
        return _FirebaseProfileMissing(
          userId: widget.userId,
          onSignOut: () => FirebaseAppService.auth.signOut(),
        );
      }

      final roleName = (data['role'] as String? ?? 'customer')
          .trim()
          .toLowerCase();
      final role = UserRole.values.firstWhere(
        (value) => value.name == roleName,
        orElse: () => UserRole.customer,
      );
      final account = Account.fromFirestore(widget.userId, data);
      if (!_notificationsStarted) {
        _notificationsStarted = true;
        unawaited(
          OrderNotificationService.startForUser(
            storeId: FirebaseAppService.storeId,
            uid: widget.userId,
          ).catchError((Object error) {
            debugPrint('Order notifications could not start: $error');
          }),
        );
      }

      return ShopShell(
        key: ValueKey(
          '${widget.userId}_${role.name}_${account.canShop}_${account.canManageStock}_${account.canCreateBills}',
        ),
        store: widget.store,
        account: account,
        onLogout: () async {
          await OrderNotificationService.stop();
          await FirebaseAppService.auth.signOut();
        },
      );
    },
  );
}

class _FirebaseProfileMissing extends StatefulWidget {
  const _FirebaseProfileMissing({
    required this.userId,
    required this.onSignOut,
  });

  final String userId;
  final VoidCallback onSignOut;

  @override
  State<_FirebaseProfileMissing> createState() =>
      _FirebaseProfileMissingState();
}

class _FirebaseProfileMissingState extends State<_FirebaseProfileMissing> {
  final _name = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseAppService.applicationDocument(widget.userId).snapshots(),
    builder: (context, snapshot) {
      final application = snapshot.data?.data();
      final status = application?['status'] as String?;
      final pending = status == 'pending';
      final approved = status == 'approved';
      final rejected = status == 'rejected';
      final email = FirebaseAppService.auth.currentUser?.email ?? '';
      final heading = pending
          ? 'Request sent for approval'
          : rejected
          ? 'Access request declined'
          : approved
          ? 'Access is being set up'
          : 'Request access to the store';
      final message = pending
          ? 'An administrator must approve your account before you can view or use the store.'
          : rejected
          ? 'Your request was declined. You can submit a new request if you still need access.'
          : approved
          ? 'Your account was approved. Sign out and sign back in if access does not open shortly.'
          : 'Create a customer account request. The app will open after an administrator approves it.';

      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline, size: 42, color: _gold),
                    const SizedBox(height: 16),
                    Text(
                      heading,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        height: 1.5,
                      ),
                    ),
                    if (snapshot.hasError) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Could not check approval status. Check your internet connection and try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: Color(0xFFAA4137),
                        ),
                      ),
                    ],
                    if (!pending && !approved) ...[
                      const SizedBox(height: 22),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 13,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Arial',
                            color: Color(0xFFAA4137),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _submitting ? null : _submitApplication,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                rejected
                                    ? 'Request approval again'
                                    : 'Request approval',
                              ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: widget.onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _submitApplication() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FirebaseAppService.submitAccountApplication(name: name);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(
          () => _error = _accountRequestError(
            error,
            fallback: 'Could not submit your request.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not submit your request. Check your internet connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

enum UserRole { admin, owner, employee, customer }

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.admin => 'Admin',
    UserRole.owner => 'Owner',
    UserRole.employee => 'Employee',
    UserRole.customer => 'Customer',
  };
}

class Account {
  Account({
    required this.id,
    required this.name,
    required this.login,
    required this.password,
    required this.role,
    required this.canShop,
    required this.canManageStock,
    required this.canCreateBills,
    this.uid,
    this.phone = '',
    this.isWalkIn = false,
  });

  factory Account.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) => Account(
    uid: uid,
    id: data['id'] as String? ?? uid,
    name: data['name'] as String? ?? '',
    login: data['email'] as String? ?? data['login'] as String? ?? '',
    password: '',
    role: UserRole.values.firstWhere(
      (role) =>
          role.name == (data['role'] as String? ?? '').trim().toLowerCase(),
      orElse: () => UserRole.customer,
    ),
    canShop: data['canShop'] == true,
    canManageStock:
        (data['role'] as String? ?? '').trim().toLowerCase() != 'customer' &&
        data['canManageStock'] == true,
    canCreateBills:
        (data['role'] as String? ?? '').trim().toLowerCase() != 'customer' &&
        data['canCreateBills'] == true,
  );

  factory Account.fromWalkIn(String id, Map<String, dynamic> data) => Account(
    id: id,
    name: data['name'] as String? ?? 'Walk-in customer',
    login: '',
    password: '',
    role: UserRole.customer,
    canShop: false,
    canManageStock: false,
    canCreateBills: false,
    phone: data['phone'] as String? ?? '',
    isWalkIn: true,
  );

  final String id;
  final String? uid;
  final String phone;
  final bool isWalkIn;
  String name;
  String login;
  String password;
  final UserRole role;
  bool canShop;
  bool canManageStock;
  bool canCreateBills;

  bool get isAdmin => role == UserRole.admin;
  bool get isOwner => role == UserRole.owner;
  bool get canSeeBusiness => isAdmin || isOwner;
}

class AccountApplication {
  const AccountApplication({
    required this.uid,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  factory AccountApplication.fromFirestore(
    String uid,
    Map<String, dynamic> data,
  ) => AccountApplication(
    uid: uid,
    name: data['name'] as String? ?? '',
    email: data['email'] as String? ?? '',
    createdAt: _storedDate(data['createdAt']),
  );

  final String uid;
  final String name;
  final String email;
  final DateTime createdAt;
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.quality,
    required this.price,
    required this.stock,
    required this.imageUrl,
    this.imageBytes,
    required this.description,
    required this.category,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Product.fromFirestore(String id, Map<String, dynamic> data) =>
      Product(
        id: id,
        name: data['name'] as String? ?? '',
        quality: data['quality'] as String? ?? '',
        price: _storedDouble(data['price']),
        stock: _storedInt(data['stock']),
        imageUrl: data['imageUrl'] as String? ?? '',
        description: data['description'] as String? ?? '',
        category: data['category'] as String? ?? '',
        createdAt: _storedDate(data['createdAt']),
      );

  final String id;
  String name;
  String quality;
  double price;
  int stock;
  String imageUrl;
  Uint8List? imageBytes;
  String description;
  String category;
  final DateTime createdAt;
}

class CartLine {
  CartLine(this.product, this.pieces);
  final Product product;
  int pieces;
  double get total => product.price * pieces;
}

class BillLine {
  const BillLine({
    required this.productId,
    required this.name,
    required this.quality,
    required this.price,
    required this.pieces,
    int? orderedPieces,
  }) : orderedPieces = orderedPieces ?? pieces;

  factory BillLine.fromFirestore(Map<String, dynamic> data) => BillLine(
    productId: data['productId'] as String? ?? '',
    name: data['name'] as String? ?? '',
    quality: data['quality'] as String? ?? '',
    price: _storedDouble(data['price']),
    pieces: _storedInt(data['pieces']),
    orderedPieces: _storedInt(data['orderedPieces']) > 0
        ? _storedInt(data['orderedPieces'])
        : _storedInt(data['pieces']),
  );

  final String productId;
  final String name;
  final String quality;
  final double price;
  final int pieces;
  final int orderedPieces;
  double get total => price * pieces;
}

enum OrderStatus { received, preparing, ready, completed }

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
    OrderStatus.received => 'Received',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.ready => 'Ready',
    OrderStatus.completed => 'Completed',
  };
}

enum PaymentMode { cash, credit }

class CustomerOrder {
  CustomerOrder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.createdAt,
    required this.billId,
    required this.lines,
    this.customerUid = '',
    this.placedByName = '',
    this.documentId = '',
  });

  factory CustomerOrder.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final order = CustomerOrder(
      id: data['id'] as String? ?? documentId,
      customerId: data['customerId'] as String? ?? '',
      customerName: data['customerName'] as String? ?? '',
      createdAt: _storedDate(data['createdAt']),
      billId: data['billId'] as String? ?? '',
      lines: (data['lines'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (line) => BillLine.fromFirestore(Map<String, dynamic>.from(line)),
          )
          .toList(),
      customerUid: data['customerUid'] as String? ?? '',
      placedByName: data['placedByName'] as String? ?? '',
      documentId: documentId,
    );
    order.status = OrderStatus.values.firstWhere(
      (status) => status.name == data['status'],
      orElse: () => OrderStatus.received,
    );
    order.seenByStaff = data['seenByStaff'] == true;
    return order;
  }

  final String id;
  final String customerId;
  final String customerName;
  final DateTime createdAt;
  final String billId;
  final List<BillLine> lines;
  final String customerUid;
  final String placedByName;
  final String documentId;
  OrderStatus status = OrderStatus.received;
  bool seenByStaff = false;
}

enum PendingStatus { pending, ready, fulfilled }

extension PendingStatusLabel on PendingStatus {
  String get label => switch (this) {
    PendingStatus.pending => 'Waiting for stock',
    PendingStatus.ready => 'Ready to order',
    PendingStatus.fulfilled => 'Purchased',
  };
}

class PendingRequest {
  PendingRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.productId,
    required this.productName,
    required this.quality,
    required this.pricePerPiece,
    required this.pieces,
    required this.createdAt,
    this.customerUid = '',
    this.documentId = '',
  });

  factory PendingRequest.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final request = PendingRequest(
      id: data['id'] as String? ?? documentId,
      customerId: data['customerId'] as String? ?? '',
      customerName: data['customerName'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      quality: data['quality'] as String? ?? '',
      pricePerPiece: _storedDouble(data['pricePerPiece']),
      pieces: _storedInt(data['pieces']),
      createdAt: _storedDate(data['createdAt']),
      customerUid: data['customerUid'] as String? ?? '',
      documentId: documentId,
    );
    request.status = PendingStatus.values.firstWhere(
      (status) => status.name == data['status'],
      orElse: () => PendingStatus.pending,
    );
    return request;
  }

  final String id;
  final String customerId;
  final String customerName;
  final String productId;
  final String productName;
  final String quality;
  final double pricePerPiece;
  final int pieces;
  final DateTime createdAt;
  final String customerUid;
  final String documentId;
  PendingStatus status = PendingStatus.pending;
}

enum ProductionTaskStatus { assigned, inProgress, completed }

class ProductionTask {
  ProductionTask({
    required this.id,
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.piecesToMake,
    required this.workerUid,
    required this.workerName,
    required this.assignedByName,
    required this.createdAt,
    this.documentId = '',
    this.status = ProductionTaskStatus.assigned,
  });

  factory ProductionTask.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final task = ProductionTask(
      id: data['id'] as String? ?? documentId,
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      currentStock: _storedInt(data['currentStock']),
      piecesToMake: _storedInt(data['piecesToMake']),
      workerUid: data['workerUid'] as String? ?? '',
      workerName: data['workerName'] as String? ?? '',
      assignedByName: data['assignedByName'] as String? ?? '',
      createdAt: _storedDate(data['createdAt']),
      documentId: documentId,
    );
    task.status = ProductionTaskStatus.values.firstWhere(
      (status) => status.name == data['status'],
      orElse: () => ProductionTaskStatus.assigned,
    );
    return task;
  }

  final String id;
  final String productId;
  final String productName;
  final int currentStock;
  final int piecesToMake;
  final String workerUid;
  final String workerName;
  final String assignedByName;
  final DateTime createdAt;
  final String documentId;
  ProductionTaskStatus status;
}

class PaymentEntry {
  const PaymentEntry({
    required this.id,
    required this.amount,
    required this.date,
    required this.note,
  });

  factory PaymentEntry.fromFirestore(Map<String, dynamic> data) => PaymentEntry(
    id: data['id'] as String? ?? '',
    amount: _storedDouble(data['amount']),
    date: _storedDate(data['date']),
    note: data['note'] as String? ?? '',
  );

  final String id;
  final double amount;
  final DateTime date;
  final String note;
}

class BusinessProfile {
  String name = 'Progressive Jewellery';
  String address = '';
  String phone = '';

  void loadFirestore(Map<String, dynamic> data) {
    name = data['name'] as String? ?? name;
    address = data['address'] as String? ?? address;
    phone = data['phone'] as String? ?? phone;
  }
}

class Bill {
  Bill({
    required this.id,
    required this.customer,
    required this.customerId,
    required this.createdAt,
    required this.lines,
    required this.paymentMode,
    required this.payments,
    this.customerUid = '',
    this.createdByName = '',
    this.documentId = '',
  });

  factory Bill.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) => Bill(
    id: data['id'] as String? ?? documentId,
    customer: data['customer'] as String? ?? '',
    customerId: data['customerId'] as String? ?? '',
    customerUid: data['customerUid'] as String? ?? '',
    createdByName: data['createdByName'] as String? ?? '',
    documentId: documentId,
    createdAt: _storedDate(data['createdAt']),
    lines: (data['lines'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((line) => BillLine.fromFirestore(Map<String, dynamic>.from(line)))
        .toList(),
    paymentMode: data['paymentMode'] == 'cash'
        ? PaymentMode.cash
        : PaymentMode.credit,
    payments: (data['payments'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (payment) =>
              PaymentEntry.fromFirestore(Map<String, dynamic>.from(payment)),
        )
        .toList(),
  );

  final String id;
  final String customer;
  final String customerId;
  final String customerUid;
  final String documentId;
  final String createdByName;
  final DateTime createdAt;
  final List<BillLine> lines;
  final PaymentMode paymentMode;
  final List<PaymentEntry> payments;
  double get total => lines.fold(0, (sum, line) => sum + line.total);
  double get paid => payments.fold(0, (sum, payment) => sum + payment.amount);
  double get balance => (total - paid).clamp(0, double.infinity).toDouble();
}

Map<String, dynamic> _accountToLocal(Account account) => {
  'id': account.id,
  'uid': account.uid,
  'name': account.name,
  'login': account.login,
  'password': account.password,
  'role': account.role.name,
  'canShop': account.canShop,
  'canManageStock': account.canManageStock,
  'canCreateBills': account.canCreateBills,
  'phone': account.phone,
  'isWalkIn': account.isWalkIn,
};

Account _accountFromLocal(Map<String, dynamic> data) => Account(
  id: data['id'] as String? ?? '',
  uid: data['uid'] as String?,
  name: data['name'] as String? ?? '',
  login: data['login'] as String? ?? '',
  password: data['password'] as String? ?? '',
  role: UserRole.values.firstWhere(
    (role) => role.name == data['role'],
    orElse: () => UserRole.customer,
  ),
  canShop: data['canShop'] == true,
  canManageStock: data['canManageStock'] == true,
  canCreateBills: data['canCreateBills'] == true,
  phone: data['phone'] as String? ?? '',
  isWalkIn: data['isWalkIn'] == true,
);

Map<String, dynamic> _productToLocal(Product item) => {
  'id': item.id,
  'name': item.name,
  'quality': item.quality,
  'price': item.price,
  'stock': item.stock,
  'imageUrl': item.imageUrl,
  'imageBytes': item.imageBytes == null ? null : base64Encode(item.imageBytes!),
  'description': item.description,
  'category': item.category,
  'createdAt': item.createdAt.toIso8601String(),
};

Product _productFromLocal(Map<String, dynamic> data) => Product(
  id: data['id'] as String? ?? '',
  name: data['name'] as String? ?? '',
  quality: data['quality'] as String? ?? '',
  price: _storedDouble(data['price']),
  stock: _storedInt(data['stock']),
  imageUrl: data['imageUrl'] as String? ?? '',
  imageBytes: data['imageBytes'] is String
      ? base64Decode(data['imageBytes'] as String)
      : null,
  description: data['description'] as String? ?? '',
  category: data['category'] as String? ?? '',
  createdAt:
      DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
);

Map<String, dynamic> _lineToLocal(BillLine line) => {
  'productId': line.productId,
  'name': line.name,
  'quality': line.quality,
  'price': line.price,
  'pieces': line.pieces,
  'orderedPieces': line.orderedPieces,
};

BillLine _lineFromLocal(Map<String, dynamic> data) => BillLine(
  productId: data['productId'] as String? ?? '',
  name: data['name'] as String? ?? '',
  quality: data['quality'] as String? ?? '',
  price: _storedDouble(data['price']),
  pieces: _storedInt(data['pieces']),
  orderedPieces: _storedInt(data['orderedPieces']) > 0
      ? _storedInt(data['orderedPieces'])
      : _storedInt(data['pieces']),
);

Map<String, dynamic> _paymentToLocal(PaymentEntry payment) => {
  'id': payment.id,
  'amount': payment.amount,
  'date': payment.date.toIso8601String(),
  'note': payment.note,
};

PaymentEntry _paymentFromLocal(Map<String, dynamic> data) => PaymentEntry(
  id: data['id'] as String? ?? '',
  amount: _storedDouble(data['amount']),
  date: DateTime.tryParse(data['date'] as String? ?? '') ?? DateTime.now(),
  note: data['note'] as String? ?? '',
);

Map<String, dynamic> _billToLocal(Bill bill) => {
  'id': bill.id,
  'customer': bill.customer,
  'customerId': bill.customerId,
  'customerUid': bill.customerUid,
  'createdByName': bill.createdByName,
  'documentId': bill.documentId,
  'createdAt': bill.createdAt.toIso8601String(),
  'lines': bill.lines.map(_lineToLocal).toList(),
  'paymentMode': bill.paymentMode.name,
  'payments': bill.payments.map(_paymentToLocal).toList(),
};

Bill _billFromLocal(Map<String, dynamic> data) => Bill(
  id: data['id'] as String? ?? '',
  customer: data['customer'] as String? ?? '',
  customerId: data['customerId'] as String? ?? '',
  customerUid: data['customerUid'] as String? ?? '',
  createdByName: data['createdByName'] as String? ?? '',
  documentId: data['documentId'] as String? ?? '',
  createdAt:
      DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
  lines: (data['lines'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => _lineFromLocal(Map<String, dynamic>.from(item)))
      .toList(),
  paymentMode: data['paymentMode'] == 'cash'
      ? PaymentMode.cash
      : PaymentMode.credit,
  payments: (data['payments'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => _paymentFromLocal(Map<String, dynamic>.from(item)))
      .toList(),
);

Map<String, dynamic> _orderToLocal(CustomerOrder order) => {
  'id': order.id,
  'customerId': order.customerId,
  'customerName': order.customerName,
  'customerUid': order.customerUid,
  'placedByName': order.placedByName,
  'documentId': order.documentId,
  'createdAt': order.createdAt.toIso8601String(),
  'billId': order.billId,
  'lines': order.lines.map(_lineToLocal).toList(),
  'status': order.status.name,
  'seenByStaff': order.seenByStaff,
};

CustomerOrder _orderFromLocal(Map<String, dynamic> data) =>
    CustomerOrder(
        id: data['id'] as String? ?? '',
        customerId: data['customerId'] as String? ?? '',
        customerName: data['customerName'] as String? ?? '',
        customerUid: data['customerUid'] as String? ?? '',
        placedByName: data['placedByName'] as String? ?? '',
        documentId: data['documentId'] as String? ?? '',
        createdAt:
            DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
        billId: data['billId'] as String? ?? '',
        lines: (data['lines'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => _lineFromLocal(Map<String, dynamic>.from(item)))
            .toList(),
      )
      ..status = OrderStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => OrderStatus.received,
      )
      ..seenByStaff = data['seenByStaff'] == true;

Map<String, dynamic> _pendingToLocal(PendingRequest request) => {
  'id': request.id,
  'customerId': request.customerId,
  'customerName': request.customerName,
  'productId': request.productId,
  'productName': request.productName,
  'quality': request.quality,
  'pricePerPiece': request.pricePerPiece,
  'pieces': request.pieces,
  'createdAt': request.createdAt.toIso8601String(),
  'customerUid': request.customerUid,
  'documentId': request.documentId,
  'status': request.status.name,
};

PendingRequest _pendingFromLocal(Map<String, dynamic> data) =>
    PendingRequest(
        id: data['id'] as String? ?? '',
        customerId: data['customerId'] as String? ?? '',
        customerName: data['customerName'] as String? ?? '',
        productId: data['productId'] as String? ?? '',
        productName: data['productName'] as String? ?? '',
        quality: data['quality'] as String? ?? '',
        pricePerPiece: _storedDouble(data['pricePerPiece']),
        pieces: _storedInt(data['pieces']),
        createdAt:
            DateTime.tryParse(data['createdAt'] as String? ?? '') ??
            DateTime.now(),
        customerUid: data['customerUid'] as String? ?? '',
        documentId: data['documentId'] as String? ?? '',
      )
      ..status = PendingStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => PendingStatus.pending,
      );

Map<String, dynamic> _productionTaskToLocal(ProductionTask task) => {
  'id': task.id,
  'productId': task.productId,
  'productName': task.productName,
  'currentStock': task.currentStock,
  'piecesToMake': task.piecesToMake,
  'workerUid': task.workerUid,
  'workerName': task.workerName,
  'assignedByName': task.assignedByName,
  'createdAt': task.createdAt.toIso8601String(),
  'documentId': task.documentId,
  'status': task.status.name,
};

ProductionTask _productionTaskFromLocal(Map<String, dynamic> data) =>
    ProductionTask(
      id: data['id'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      currentStock: _storedInt(data['currentStock']),
      piecesToMake: _storedInt(data['piecesToMake']),
      workerUid: data['workerUid'] as String? ?? '',
      workerName: data['workerName'] as String? ?? '',
      assignedByName: data['assignedByName'] as String? ?? '',
      createdAt:
          DateTime.tryParse(data['createdAt'] as String? ?? '') ??
          DateTime.now(),
      documentId: data['documentId'] as String? ?? '',
      status: ProductionTaskStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => ProductionTaskStatus.assigned,
      ),
    );

Map<String, Map<String, CartLine>> _restoreLocalCarts(Object? value) {
  if (value is! Map) return {};
  return value.map((accountId, items) {
    final lines = <String, CartLine>{};
    if (items is Map) {
      for (final entry in items.entries) {
        final pieces = _storedInt(entry.value);
        if (pieces < 1) continue;
        lines[entry.key.toString()] = CartLine(
          Product(
            id: entry.key.toString(),
            name: '',
            quality: '',
            price: 0,
            stock: 0,
            imageUrl: '',
            description: '',
            category: '',
          ),
          pieces,
        );
      }
    }
    return MapEntry(accountId.toString(), lines);
  });
}

class AppStore {
  AppStore({this.firebaseEnabled = false, bool seedDemoData = true}) {
    if (!seedDemoData) return;
    accounts.add(
      Account(
        id: 'ADM-001',
        name: 'Store administrator',
        login: 'admin@progressivejewellery.com',
        password: 'admin123',
        role: UserRole.admin,
        canShop: true,
        canManageStock: true,
        canCreateBills: true,
      ),
    );
    products.addAll([
      Product(
        id: 'PJ-RNG-001',
        name: 'The Heirloom Band',
        quality: '18K gold · Hallmarked',
        price: 24800,
        stock: 12,
        category: 'Rings',
        description:
            'A softly sculpted gold band, made to become part of your story.',
        imageUrl: 'https://images.unsplash.com/photo-1605100804763-247f67b3557e?auto=format&fit=crop&w=1100&q=85',
      ),
      Product(
        id: 'PJ-NCK-002',
        name: 'Solstice Pendant',
        quality: '22K gold · Hallmarked',
        price: 42900,
        stock: 8,
        category: 'Necklaces',
        description:
            'A radiant pendant with a fine chain and a warm, polished finish.',
        imageUrl: 'https://images.unsplash.com/photo-1599643478518-a784e5dc4c8f?auto=format&fit=crop&w=1100&q=85',
      ),
      Product(
        id: 'PJ-ERN-003',
        name: 'Dawn Drop Earrings',
        quality: '18K gold · Pair',
        price: 18600,
        stock: 16,
        category: 'Earrings',
        description:
            'Light-catching drops with an easy silhouette for every day.',
        imageUrl: 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=1100&q=85',
      ),
      Product(
        id: 'PJ-BRC-004',
        name: 'Mira Chain Bracelet',
        quality: '14K gold · Adjustable',
        price: 21500,
        stock: 6,
        category: 'Bracelets',
        description:
            'A delicate chain bracelet finished with a small, signature charm.',
        imageUrl: 'https://images.unsplash.com/photo-1611652022419-a9419f74343d?auto=format&fit=crop&w=1100&q=85',
      ),
    ]);
    categories.addAll(['Rings', 'Necklaces', 'Earrings', 'Bracelets']);
  }

  final bool firebaseEnabled;

  final List<Account> accounts = [];
  final List<AccountApplication> accountApplications = [];
  final List<Account> manualCustomers = [];
  final List<Product> products = [];
  final Map<String, Map<String, CartLine>> cartsByAccount = {};
  final List<Bill> bills = [];
  final List<CustomerOrder> orders = [];
  final List<PendingRequest> pendingRequests = [];
  final List<ProductionTask> productionTasks = [];
  final Set<String> categories = {};
  final BusinessProfile business = BusinessProfile();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _localWriteQueue = Future<void>.value();
  int _syncGeneration = 0;

  Future<void> loadLocalData() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('local_store_v1');
    if (saved == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      accounts
        ..clear()
        ..addAll(
          (data['accounts'] as List<dynamic>? ?? const []).whereType<Map>().map(
            (item) => _accountFromLocal(Map<String, dynamic>.from(item)),
          ),
        );
      manualCustomers
        ..clear()
        ..addAll(
          (data['manualCustomers'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => _accountFromLocal(Map<String, dynamic>.from(item)),
              ),
        );
      products
        ..clear()
        ..addAll(
          (data['products'] as List<dynamic>? ?? const []).whereType<Map>().map(
            (item) => _productFromLocal(Map<String, dynamic>.from(item)),
          ),
        );
      bills
        ..clear()
        ..addAll(
          (data['bills'] as List<dynamic>? ?? const []).whereType<Map>().map(
            (item) => _billFromLocal(Map<String, dynamic>.from(item)),
          ),
        );
      orders
        ..clear()
        ..addAll(
          (data['orders'] as List<dynamic>? ?? const []).whereType<Map>().map(
            (item) => _orderFromLocal(Map<String, dynamic>.from(item)),
          ),
        );
      pendingRequests
        ..clear()
        ..addAll(
          (data['pendingRequests'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) => _pendingFromLocal(Map<String, dynamic>.from(item)),
              ),
        );
      productionTasks
        ..clear()
        ..addAll(
          (data['productionTasks'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    _productionTaskFromLocal(Map<String, dynamic>.from(item)),
              ),
        );
      categories
        ..clear()
        ..addAll(
          (data['categories'] as List<dynamic>? ?? const [])
              .whereType<String>(),
        );
      cartsByAccount
        ..clear()
        ..addAll(_restoreLocalCarts(data['carts']));
      for (final cart in cartsByAccount.values) {
        for (final entry in cart.entries.toList()) {
          Product? product;
          for (final candidate in products) {
            if (candidate.id == entry.key) {
              product = candidate;
              break;
            }
          }
          if (product == null) {
            cart.remove(entry.key);
          } else {
            cart[entry.key] = CartLine(product, entry.value.pieces);
          }
        }
      }
      final businessData = data['business'];
      if (businessData is Map) {
        business
          ..name = businessData['name'] as String? ?? business.name
          ..address = businessData['address'] as String? ?? ''
          ..phone = businessData['phone'] as String? ?? '';
      }
    } catch (error) {
      debugPrint('Saved local store data could not be read: $error');
    }
  }

  Future<void> persistLocalData() {
    if (firebaseEnabled) return Future<void>.value();
    final payload = jsonEncode({
      'accounts': accounts.map(_accountToLocal).toList(),
      'manualCustomers': manualCustomers.map(_accountToLocal).toList(),
      'products': products.map(_productToLocal).toList(),
      'bills': bills.map(_billToLocal).toList(),
      'orders': orders.map(_orderToLocal).toList(),
      'pendingRequests': pendingRequests.map(_pendingToLocal).toList(),
      'productionTasks': productionTasks.map(_productionTaskToLocal).toList(),
      'categories': categories.toList(),
      'carts': cartsByAccount.map(
        (accountId, cart) => MapEntry(
          accountId,
          cart.map((productId, line) => MapEntry(productId, line.pieces)),
        ),
      ),
      'business': {
        'name': business.name,
        'address': business.address,
        'phone': business.phone,
      },
    });
    _localWriteQueue = _localWriteQueue
        .catchError((error) {
          debugPrint('A previous local save failed: $error');
        })
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString('local_store_v1', payload);
        });
    return _localWriteQueue;
  }

  Map<String, CartLine> cartFor(Account account) =>
      cartsByAccount.putIfAbsent(account.id, () => <String, CartLine>{});

  Account? authenticate(String login, String password) {
    final normalized = login.trim().toLowerCase();
    for (final account in accounts) {
      if (account.login.toLowerCase() == normalized &&
          account.password == password) {
        return account;
      }
    }
    return null;
  }

  Future<void> startFirestoreSync(
    Account account,
    VoidCallback onChanged,
  ) async {
    final generation = ++_syncGeneration;
    await _cancelFirestoreSubscriptions();
    if (generation != _syncGeneration ||
        !firebaseEnabled ||
        account.uid == null) {
      return;
    }
    final storePath = 'stores/${FirebaseAppService.storeId}';
    final firestore = FirebaseAppService.firestore;
    final syncedCartItems = <String, int>{};

    void restoreCart() {
      final cart = <String, CartLine>{};
      for (final entry in syncedCartItems.entries) {
        final product = _findProduct(entry.key);
        if (product != null && entry.value > 0) {
          cart[entry.key] = CartLine(product, entry.value);
        }
      }
      cartsByAccount[account.id] = cart;
    }

    _subscriptions.add(
      firestore.collection('$storePath/products').snapshots().listen((
        snapshot,
      ) {
        products
          ..clear()
          ..addAll(
            snapshot.docs.map(
              (doc) => Product.fromFirestore(doc.id, doc.data()),
            ),
          );
        restoreCart();
        onChanged();
      }),
    );
    _subscriptions.add(
      firestore.collection('$storePath/categories').snapshots().listen((
        snapshot,
      ) {
        categories
          ..clear()
          ..addAll(
            snapshot.docs.map((doc) => doc.data()['name'] as String? ?? doc.id),
          );
        onChanged();
      }),
    );

    if (account.role != UserRole.customer &&
        (account.canCreateBills || account.canSeeBusiness || account.isAdmin)) {
      _subscriptions.add(
        firestore.collection('$storePath/customers').snapshots().listen((
          snapshot,
        ) {
          manualCustomers
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => Account.fromWalkIn(doc.id, doc.data()),
              ),
            );
          onChanged();
        }),
      );
    } else {
      manualCustomers.clear();
    }

    final uid = account.uid!;
    final cartDocument = firestore.doc('$storePath/carts/$uid');
    _subscriptions.add(
      cartDocument.snapshots().listen((snapshot) {
        final items = snapshot.data()?['items'];
        syncedCartItems.clear();
        if (items is Map) {
          for (final entry in items.entries) {
            final productId = entry.key.toString();
            final pieces = _storedInt(entry.value);
            if (pieces > 0) syncedCartItems[productId] = pieces;
          }
        }
        restoreCart();
        onChanged();
      }),
    );

    Query<Map<String, dynamic>> orders = firestore.collection(
      '$storePath/orders',
    );
    Query<Map<String, dynamic>> bills = firestore.collection(
      '$storePath/bills',
    );
    Query<Map<String, dynamic>> requests = firestore.collection(
      '$storePath/pendingRequests',
    );
    if (account.role == UserRole.customer) {
      orders = orders.where('customerUid', isEqualTo: uid);
      bills = bills.where('customerUid', isEqualTo: uid);
      requests = requests.where('customerUid', isEqualTo: uid);
    }
    if (account.role == UserRole.customer ||
        account.isAdmin ||
        account.isOwner ||
        account.canShop ||
        account.canCreateBills) {
      _subscriptions.add(
        orders.snapshots().listen((snapshot) {
          this.orders
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => CustomerOrder.fromFirestore(doc.id, doc.data()),
              ),
            );
          this.orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          onChanged();
        }),
      );
      _subscriptions.add(
        requests.snapshots().listen((snapshot) {
          pendingRequests
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => PendingRequest.fromFirestore(doc.id, doc.data()),
              ),
            );
          onChanged();
        }),
      );
    } else {
      this.orders.clear();
      pendingRequests.clear();
    }
    Query<Map<String, dynamic>> tasks = firestore.collection(
      '$storePath/productionTasks',
    );
    if (account.role == UserRole.employee) {
      tasks = tasks.where('workerUid', isEqualTo: uid);
    }
    if (account.role != UserRole.customer) {
      _subscriptions.add(
        tasks.snapshots().listen((snapshot) {
          productionTasks
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => ProductionTask.fromFirestore(doc.id, doc.data()),
              ),
            );
          productionTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          onChanged();
        }),
      );
    }
    if (account.role == UserRole.customer ||
        account.isAdmin ||
        account.isOwner ||
        account.canCreateBills ||
        account.canSeeBusiness) {
      _subscriptions.add(
        bills.snapshots().listen((snapshot) {
          this.bills
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => Bill.fromFirestore(doc.id, doc.data()),
              ),
            );
          this.bills.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          onChanged();
        }),
      );
    } else {
      this.bills.clear();
    }
    _subscriptions.add(
      firestore.doc('$storePath/business/profile').snapshots().listen((
        snapshot,
      ) {
        if (snapshot.exists) business.loadFirestore(snapshot.data()!);
        onChanged();
      }),
    );
    if (account.canSeeBusiness || account.isAdmin || account.canCreateBills) {
      _subscriptions.add(
        firestore.collection('$storePath/members').snapshots().listen((
          snapshot,
        ) {
          accounts
            ..clear()
            ..addAll(
              snapshot.docs.map(
                (doc) => Account.fromFirestore(doc.id, doc.data()),
              ),
            );
          onChanged();
        }),
      );
    } else {
      accounts
        ..clear()
        ..add(account);
    }
    if (account.isAdmin) {
      _subscriptions.add(
        firestore
            .collection('$storePath/applications')
            .where('status', isEqualTo: 'pending')
            .snapshots()
            .listen((snapshot) {
              accountApplications
                ..clear()
                ..addAll(
                  snapshot.docs.map(
                    (doc) =>
                        AccountApplication.fromFirestore(doc.id, doc.data()),
                  ),
                );
              accountApplications.sort(
                (a, b) => a.createdAt.compareTo(b.createdAt),
              );
              onChanged();
            }),
      );
    } else {
      accountApplications.clear();
    }
  }

  Future<void> refreshFromServer(Account account) async {
    if (!firebaseEnabled || account.uid == null) {
      throw StateError('The shared store database is not connected.');
    }

    final storePath = 'stores/${FirebaseAppService.storeId}';
    final firestore = FirebaseAppService.firestore;
    const server = GetOptions(source: Source.server);

    final productSnapshot = await firestore
        .collection('$storePath/products')
        .get(server);
    final categorySnapshot = await firestore
        .collection('$storePath/categories')
        .get(server);

    final existingCarts = cartsByAccount.map(
      (accountId, cart) =>
          MapEntry(accountId, Map<String, CartLine>.from(cart)),
    );
    products
      ..clear()
      ..addAll(
        productSnapshot.docs.map(
          (doc) => Product.fromFirestore(doc.id, doc.data()),
        ),
      );
    final refreshedProducts = {
      for (final product in products) product.id: product,
    };
    for (final entry in existingCarts.entries) {
      final cart = cartsByAccount.putIfAbsent(
        entry.key,
        () => <String, CartLine>{},
      );
      cart
        ..clear()
        ..addAll(
          entry.value.map((productId, line) {
            final refreshedProduct = refreshedProducts[productId];
            return MapEntry(
              productId,
              refreshedProduct == null
                  ? line
                  : CartLine(refreshedProduct, line.pieces),
            );
          }),
        );
    }
    categories
      ..clear()
      ..addAll(
        categorySnapshot.docs.map(
          (doc) => doc.data()['name'] as String? ?? doc.id,
        ),
      );

    final uid = account.uid!;
    Query<Map<String, dynamic>> orders = firestore.collection(
      '$storePath/orders',
    );
    Query<Map<String, dynamic>> bills = firestore.collection(
      '$storePath/bills',
    );
    Query<Map<String, dynamic>> requests = firestore.collection(
      '$storePath/pendingRequests',
    );
    if (account.role == UserRole.customer) {
      orders = orders.where('customerUid', isEqualTo: uid);
      bills = bills.where('customerUid', isEqualTo: uid);
      requests = requests.where('customerUid', isEqualTo: uid);
    }

    if (account.role != UserRole.customer &&
        (account.canCreateBills || account.canSeeBusiness || account.isAdmin)) {
      final customerSnapshot = await firestore
          .collection('$storePath/customers')
          .get(server);
      manualCustomers
        ..clear()
        ..addAll(
          customerSnapshot.docs.map(
            (doc) => Account.fromWalkIn(doc.id, doc.data()),
          ),
        );
    } else {
      manualCustomers.clear();
    }

    if (account.role == UserRole.customer ||
        account.isAdmin ||
        account.isOwner ||
        account.canShop ||
        account.canCreateBills) {
      final orderSnapshot = await orders.get(server);
      final requestSnapshot = await requests.get(server);
      this.orders
        ..clear()
        ..addAll(
          orderSnapshot.docs.map(
            (doc) => CustomerOrder.fromFirestore(doc.id, doc.data()),
          ),
        )
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      pendingRequests
        ..clear()
        ..addAll(
          requestSnapshot.docs.map(
            (doc) => PendingRequest.fromFirestore(doc.id, doc.data()),
          ),
        );
    }

    if (account.role != UserRole.customer) {
      Query<Map<String, dynamic>> tasks = firestore.collection(
        '$storePath/productionTasks',
      );
      if (account.role == UserRole.employee) {
        tasks = tasks.where('workerUid', isEqualTo: uid);
      }
      final taskSnapshot = await tasks.get(server);
      productionTasks
        ..clear()
        ..addAll(
          taskSnapshot.docs.map(
            (doc) => ProductionTask.fromFirestore(doc.id, doc.data()),
          ),
        )
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    if (account.role == UserRole.customer ||
        account.isAdmin ||
        account.isOwner ||
        account.canCreateBills ||
        account.canSeeBusiness) {
      final billSnapshot = await bills.get(server);
      this.bills
        ..clear()
        ..addAll(
          billSnapshot.docs.map(
            (doc) => Bill.fromFirestore(doc.id, doc.data()),
          ),
        )
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    final businessSnapshot = await firestore
        .doc('$storePath/business/profile')
        .get(server);
    if (businessSnapshot.exists) {
      business.loadFirestore(businessSnapshot.data()!);
    }

    if (account.canSeeBusiness || account.isAdmin || account.canCreateBills) {
      final memberSnapshot = await firestore
          .collection('$storePath/members')
          .get(server);
      accounts
        ..clear()
        ..addAll(
          memberSnapshot.docs.map(
            (doc) => Account.fromFirestore(doc.id, doc.data()),
          ),
        );
    }

    if (account.isAdmin) {
      final applicationSnapshot = await firestore
          .collection('$storePath/applications')
          .where('status', isEqualTo: 'pending')
          .get(server);
      accountApplications
        ..clear()
        ..addAll(
          applicationSnapshot.docs.map(
            (doc) => AccountApplication.fromFirestore(doc.id, doc.data()),
          ),
        );
    }
  }

  Future<void> stopFirestoreSync() async {
    _syncGeneration++;
    await _cancelFirestoreSubscriptions();
  }

  Future<void> _cancelFirestoreSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Product? _findProduct(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Future<void> persistCart(Account account) async {
    if (!firebaseEnabled) {
      await persistLocalData();
      return;
    }
    if (account.uid == null) return;
    final items = cartFor(account).map((id, line) => MapEntry(id, line.pieces));
    await FirebaseAppService.saveCart(account.uid!, items);
  }

  Future<void> persistProduct(Product product) async {
    if (!firebaseEnabled) {
      await persistLocalData();
      return;
    }
    product.imageUrl = await FirebaseAppService.saveProduct(
      id: product.id,
      name: product.name,
      quality: product.quality,
      price: product.price,
      stock: product.stock,
      imageUrl: product.imageUrl,
      imageBytes: product.imageBytes,
      description: product.description,
      category: product.category,
      createdAt: product.createdAt,
    );
    product.imageBytes = null;
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.store,
    required this.onLogin,
    this.firebaseAuthEnabled = false,
  });
  final AppStore store;
  final ValueChanged<Account> onLogin;
  final bool firebaseAuthEnabled;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (width >= 850)
              Expanded(
                flex: 6,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF292723),
                        Color(0xFF65533B),
                        Color(0xFFB08A48),
                      ],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        'https://images.unsplash.com/photo-1617038220319-276d3cfab638?auto=format&fit=crop&w=1600&q=85',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                      Container(color: const Color(0x990F0D0A)),
                      Padding(
                        padding: const EdgeInsets.all(64),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _BrandLockup(light: true),
                            const Spacer(),
                            const Text(
                              'Made to be\nremembered.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 58,
                                height: 1.12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Fine pieces. Thoughtfully chosen.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .74),
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 52),
                            const _Overline(
                              'PROGRESSIVE JEWELLERY  ·  EST. 2024',
                              light: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              flex: width >= 850 ? 4 : 1,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 40,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 410),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (width < 850) const _BrandLockup(),
                          if (width < 850) const SizedBox(height: 54),
                          const _Overline('YOUR JEWELLERY HOUSE'),
                          const SizedBox(height: 14),
                          const Text(
                            'Welcome back',
                            style: TextStyle(fontSize: 38, height: 1.15),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.firebaseAuthEnabled
                                ? 'Sign in with your email address to continue.'
                                : 'Sign in with your email or phone number to continue.',
                            style: TextStyle(
                              color: _muted,
                              fontFamily: 'Arial',
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 34),
                          TextFormField(
                            controller: _login,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: widget.firebaseAuthEnabled
                                  ? 'Email address'
                                  : 'Email or phone number',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter your email address'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Enter your password'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFAA4137),
                                fontFamily: 'Arial',
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Sign in',
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (widget.firebaseAuthEnabled) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _registerCustomer,
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Create customer account'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'New accounts need admin approval before they can use the store.',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 30),
                            const Divider(color: _line),
                            const SizedBox(height: 15),
                            const Text(
                              'Demo administrator access',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Email  admin@progressivejewellery.com\nPassword  admin123',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: _muted,
                                height: 1.7,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Ask your administrator to create your account.',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.firebaseAuthEnabled) {
      try {
        await FirebaseAppService.auth.signInWithEmailAndPassword(
          email: _login.text.trim().toLowerCase(),
          password: _password.text,
        );
        if (mounted) setState(() => _error = null);
      } on FirebaseAuthException catch (error) {
        if (!mounted) return;
        setState(() {
          _error = switch (error.code) {
            'invalid-credential' ||
            'user-not-found' ||
            'wrong-password' => 'Email or password is incorrect.',
            'too-many-requests' =>
              'Too many attempts. Wait a moment and try again.',
            'network-request-failed' =>
              'Check your internet connection and try again.',
            _ => error.message ?? 'Could not sign in. Try again.',
          };
        });
      } catch (_) {
        if (mounted) setState(() => _error = 'Could not sign in. Try again.');
      }
      return;
    }

    final account = widget.store.authenticate(_login.text, _password.text);
    if (account == null) {
      setState(
        () => _error = 'We could not find an account with those details.',
      );
    } else {
      widget.onLogin(account);
    }
  }

  Future<void> _registerCustomer() => showDialog<void>(
    context: context,
    builder: (_) => const _CustomerRegistrationDialog(),
  );
}

class _CustomerRegistrationDialog extends StatefulWidget {
  const _CustomerRegistrationDialog();

  @override
  State<_CustomerRegistrationDialog> createState() =>
      _CustomerRegistrationDialogState();
}

class _CustomerRegistrationDialogState
    extends State<_CustomerRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create customer account'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'An administrator must approve your request before you can use the store.',
                style: TextStyle(fontFamily: 'Arial', height: 1.4),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) =>
                    value == null ||
                        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(value.trim())
                    ? 'Enter a valid email address'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) => value == null || value.length < 6
                    ? 'Use at least 6 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (value) =>
                    value != _password.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    color: Color(0xFFAA4137),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _createAccount,
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Send request'),
      ),
    ],
  );

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final credential = await FirebaseAppService.auth
          .createUserWithEmailAndPassword(
            email: _email.text.trim().toLowerCase(),
            password: _password.text,
          );
      await credential.user?.updateDisplayName(_name.text.trim());
      await FirebaseAppService.submitAccountApplication(name: _name.text);
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'email-already-in-use' =>
            'An account already uses this email. Sign in to request access.',
          'invalid-email' => 'Enter a valid email address.',
          'weak-password' => 'Choose a stronger password.',
          'network-request-failed' =>
            'Check your internet connection and try again.',
          _ => error.message ?? 'Could not create the account.',
        };
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              _accountRequestError(
                error,
                fallback: 'The request could not be sent. Sign in to retry.',
              ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not create the account. Check your internet connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

enum _Page {
  customerDashboard,
  shop,
  inventory,
  production,
  cart,
  orders,
  pending,
  bills,
  customers,
  statistics,
  team,
  settings,
  account,
  access,
}

enum _ProductSort { recent, priceLowToHigh, priceHighToLow, name }

enum _StockFilter { all, inStock, outOfStock }

class ShopShell extends StatefulWidget {
  const ShopShell({
    super.key,
    required this.store,
    required this.account,
    required this.onLogout,
  });
  final AppStore store;
  final Account account;
  final VoidCallback onLogout;

  @override
  State<ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends State<ShopShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  _Page _page = _Page.shop;
  String _query = '';
  String _category = 'All pieces';
  _ProductSort _productSort = _ProductSort.recent;
  _StockFilter _stockFilter = _StockFilter.all;

  bool get _canShop =>
      widget.account.canShop ||
      widget.account.isAdmin ||
      widget.account.isOwner;
  bool get _canManageStock =>
      widget.account.canManageStock ||
      widget.account.isAdmin ||
      widget.account.isOwner;
  bool get _canCreateBills =>
      widget.account.canCreateBills ||
      widget.account.isAdmin ||
      widget.account.isOwner;

  @override
  void initState() {
    super.initState();
    if (widget.account.role == UserRole.customer) {
      _page = _Page.customerDashboard;
    }
    unawaited(
      widget.store.startFirestoreSync(widget.account, () {
        if (!mounted) return;
        for (final product in widget.store.products) {
          _refreshPendingStatuses(product);
        }
        setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    unawaited(widget.store.stopFirestoreSync());
    super.dispose();
  }

  Map<String, CartLine> get _cart => widget.store.cartFor(widget.account);

  int get _pieceCount => _cart.values.fold(0, (sum, line) => sum + line.pieces);

  int _reservedPieces(Product product) => widget.store.cartsByAccount.values
      .fold(0, (sum, cart) => sum + (cart[product.id]?.pieces ?? 0));

  int _availablePieces(Product product) =>
      (product.stock - _reservedPieces(product)).clamp(0, 1 << 30).toInt();

  int get _unseenOrders => widget.account.role == UserRole.customer
      ? 0
      : widget.store.orders.where((order) => !order.seenByStaff).length;

  List<_Page> get _pages {
    final pages = <_Page>[];
    if (widget.account.role == UserRole.customer) {
      pages.add(_Page.customerDashboard);
    }
    if (_canShop) pages.add(_Page.shop);
    if (_canManageStock) pages.add(_Page.inventory);
    if (widget.account.role != UserRole.customer) {
      pages.add(_Page.production);
    }
    if (_canShop) pages.add(_Page.cart);
    if (_canShop || _canCreateBills) {
      pages.add(_Page.orders);
    }
    if (widget.account.role == UserRole.customer) {
      pages.addAll([_Page.pending, _Page.bills]);
    } else if (_canCreateBills) {
      pages.add(_Page.bills);
    }
    if (widget.account.canSeeBusiness) {
      pages.addAll([_Page.customers, _Page.statistics, _Page.settings]);
    }
    if (widget.account.isAdmin || widget.account.isOwner) {
      pages.add(_Page.team);
    }
    pages.add(_Page.account);
    if (pages.isEmpty) pages.add(_Page.access);
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1000;
    final page = _pages.contains(_page) ? _page : _pages.first;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: desktop
          ? null
          : Drawer(
              width: 280,
              child: SafeArea(
                child: _Sidebar(
                  width: 280,
                  compact: true,
                  account: widget.account,
                  page: page,
                  pages: _pages,
                  cartCount: _pieceCount,
                  orderCount: _unseenOrders,
                  onSelect: (next) {
                    setState(() => _page = next);
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                  onLogout: widget.onLogout,
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              _Sidebar(
                account: widget.account,
                width: 244,
                compact: false,
                page: page,
                pages: _pages,
                cartCount: _pieceCount,
                orderCount: _unseenOrders,
                onSelect: (next) => setState(() => _page = next),
                onLogout: widget.onLogout,
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    account: widget.account,
                    onMenu: desktop
                        ? null
                        : () => _scaffoldKey.currentState?.openDrawer(),
                    cartCount: _pieceCount,
                    orderCount: _unseenOrders,
                    onSearch: (value) => setState(() {
                      _query = value;
                      _page = _Page.shop;
                    }),
                    onCart: _canShop
                        ? () => setState(() => _page = _Page.cart)
                        : null,
                    onOrders: _pages.contains(_Page.orders)
                        ? () => setState(() => _page = _Page.orders)
                        : null,
                    onLogout: widget.onLogout,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: _paper,
                      child: RefreshIndicator(
                        onRefresh: _refreshFromInternet,
                        notificationPredicate: (notification) =>
                            page != _Page.access && notification.depth == 0,
                        child: _buildPage(page),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_Page page) => switch (page) {
    _Page.customerDashboard => _customerDashboardPage(),
    _Page.shop => _shopPage(),
    _Page.inventory => _inventoryPage(),
    _Page.production => _productionPage(),
    _Page.cart => _cartPage(),
    _Page.bills => _billsPage(),
    _Page.orders => _ordersPage(),
    _Page.pending => _pendingPage(),
    _Page.customers => _customersPage(),
    _Page.statistics => _statisticsPage(),
    _Page.settings => _settingsPage(),
    _Page.account => _accountPage(),
    _Page.team => _teamPage(),
    _Page.access => const _AccessPage(),
  };

  Future<void> _refreshFromInternet() async {
    try {
      await widget.store.refreshFromServer(widget.account);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _snack('Could not refresh from the internet: $error');
    }
  }

  Widget _customerDashboardPage() {
    final customerOrders = widget.store.orders
        .where((order) => order.customerId == widget.account.id)
        .toList();
    final customerBills = widget.store.bills
        .where((bill) => bill.customerId == widget.account.id)
        .toList();
    final customerPending = widget.store.pendingRequests
        .where((request) => request.customerId == widget.account.id)
        .toList();
    return CustomerDashboardPage(
      customerName: widget.account.name,
      orders: customerOrders,
      bills: customerBills,
      pendingRequests: customerPending,
      onBrowse: () => setState(() => _page = _Page.shop),
      onOpenOrders: () => setState(() => _page = _Page.orders),
      onOpenBills: () => setState(() => _page = _Page.bills),
      onOpenPending: () => setState(() => _page = _Page.pending),
    );
  }

  void _openProductDetails(Product product) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ProductDetailsPage(
          product: product,
          allowCart: _canShop,
          availablePieces: _availablePieces(product),
          onAdd: (pieces) => _addToCart(product, pieces),
          onRequestPending: () => _requestPending(product),
        ),
      ),
    );
  }

  Widget _shopPage() {
    final items = widget.store.products.where((product) {
      final text =
          '${product.name} ${product.id} ${product.quality} ${product.category}'
              .toLowerCase();
      final matchesStock = switch (_stockFilter) {
        _StockFilter.all => true,
        _StockFilter.inStock => _availablePieces(product) > 0,
        _StockFilter.outOfStock => _availablePieces(product) == 0,
      };
      return text.contains(_query.toLowerCase()) &&
          (_category == 'All pieces' || product.category == _category) &&
          matchesStock;
    }).toList();
    items.sort(
      (a, b) => switch (_productSort) {
        _ProductSort.recent => b.createdAt.compareTo(a.createdAt),
        _ProductSort.priceLowToHigh => a.price.compareTo(b.price),
        _ProductSort.priceHighToLow => b.price.compareTo(a.price),
        _ProductSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      },
    );
    final categories = ['All pieces', ...widget.store.categories];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1250
            ? 3
            : constraints.maxWidth >= 740
            ? 2
            : 1;
        final ratio = columns == 1 ? .76 : .7;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              sliver: SliverToBoxAdapter(
                child: _ShopHero(
                  name: widget.account.name,
                  productCount: widget.store.products.length,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 13),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'The collection',
                        style: TextStyle(fontSize: 27),
                      ),
                    ),
                    Text(
                      '${items.length} pieces',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
              sliver: SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories
                        .map(
                          (category) => Padding(
                            padding: const EdgeInsets.only(right: 9),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _category == category,
                              onSelected: (_) =>
                                  setState(() => _category = category),
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                color: _category == category
                                    ? Colors.white
                                    : _ink,
                                fontFamily: 'Arial',
                                fontSize: 12,
                              ),
                              selectedColor: _ink,
                              side: const BorderSide(color: _line),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 9),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _productFilter<_ProductSort>(
                      label: 'Sort by',
                      value: _productSort,
                      items: const {
                        _ProductSort.recent: 'Recently added',
                        _ProductSort.priceLowToHigh: 'Price: low to high',
                        _ProductSort.priceHighToLow: 'Price: high to low',
                        _ProductSort.name: 'Name',
                      },
                      onChanged: (value) =>
                          setState(() => _productSort = value),
                    ),
                    _productFilter<_StockFilter>(
                      label: 'Availability',
                      value: _stockFilter,
                      items: const {
                        _StockFilter.all: 'All stock',
                        _StockFilter.inStock: 'In stock',
                        _StockFilter.outOfStock: 'Out of stock',
                      },
                      onChanged: (value) =>
                          setState(() => _stockFilter = value),
                    ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No pieces found. Try a different search.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 9, 28, 34),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      key: ValueKey(items[index].id),
                      product: items[index],
                      allowCart: _canShop,
                      availablePieces: _availablePieces(items[index]),
                      onAdd: (pieces) => _addToCart(items[index], pieces),
                      onRequestPending: () => _requestPending(items[index]),
                      onOpenDetails: () => _openProductDetails(items[index]),
                    ),
                    childCount: items.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: ratio,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _productFilter<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) => Container(
    width: 205,
    height: 54,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        icon: const Icon(Icons.expand_more, size: 19),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
        selectedItemBuilder: (context) => items.entries
            .map(
              (entry) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$label: ${entry.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 11,
                    color: _ink,
                  ),
                ),
              ),
            )
            .toList(),
        items: items.entries
            .map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 11),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );

  Widget _inventoryPage() => InventoryPage(
    products: widget.store.products,
    categories: widget.store.categories,
    pendingRequests: widget.store.pendingRequests,
    onCategoryAdded: (category) {
      setState(() {
        widget.store.categories.add(category);
        _category = 'All pieces';
      });
      unawaited(_persist(() => FirebaseAppService.saveCategory(category)));
    },
    onChanged: (product) {
      setState(() {
        widget.store.categories.add(product.category);
        if (!widget.store.firebaseEnabled) {
          _refreshPendingStatuses(product);
        }
      });
      unawaited(
        _persist(() => FirebaseAppService.saveCategory(product.category)),
      );
      unawaited(_persist(() => widget.store.persistProduct(product)));
    },
  );

  Widget _productionPage() => ProductionTasksPage(
    account: widget.account,
    tasks: widget.store.productionTasks
        .where(
          (task) =>
              widget.account.role != UserRole.employee ||
              task.workerUid == (widget.account.uid ?? widget.account.id),
        )
        .toList(),
    products: widget.store.products,
    workers: widget.store.accounts
        .where((account) => account.role == UserRole.employee)
        .toList(),
    canAssign: widget.account.canSeeBusiness,
    onAssign: _assignProductionTask,
    onStatusChanged: _updateProductionTaskStatus,
  );

  Widget _cartPage() => CartPage(
    cart: _cart,
    onChanged: () {
      setState(() {});
      unawaited(_persist(() => widget.store.persistCart(widget.account)));
    },
    onCheckout: _checkout,
    allowOrdering: widget.account.role == UserRole.customer || _canCreateBills,
  );

  Widget _billsPage() {
    final bills = widget.account.role == UserRole.customer
        ? widget.store.bills
              .where((bill) => bill.customerId == widget.account.id)
              .toList()
        : widget.store.bills;
    final staffCanEdit =
        widget.account.role != UserRole.customer && _canCreateBills;
    return BillsPage(
      bills: bills,
      onDownload: _downloadReceipt,
      canEditPrices: staffCanEdit,
      onEditLinePrice: staffCanEdit ? _editBillLinePrice : null,
      onEditLineQuantity: staffCanEdit ? _editBillLineQuantity : null,
      onAddSale: staffCanEdit ? () => setState(() => _page = _Page.shop) : null,
    );
  }

  Widget _pendingPage() {
    final requests =
        widget.store.pendingRequests
            .where((request) => request.customerId == widget.account.id)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return PendingItemsPage(
      requests: requests,
      products: widget.store.products,
      onAdd: _addPendingToCart,
      onRefresh: (product) => setState(() => _refreshPendingStatuses(product)),
    );
  }

  Widget _ordersPage() => OrdersPage(
    orders: widget.store.orders,
    pendingRequests: widget.store.pendingRequests,
    products: widget.store.products,
    bills: widget.store.bills,
    account: widget.account,
    onOrderStatusChanged: (order, status) {
      if (widget.store.firebaseEnabled && order.documentId.isNotEmpty) {
        unawaited(
          _persist(
            () => FirebaseAppService.updateOrderStatus(
              orderDocumentId: order.documentId,
              status: status.name,
            ),
          ),
        );
      } else {
        setState(() {
          order.status = status;
          order.seenByStaff = true;
        });
        unawaited(widget.store.persistLocalData());
      }
    },
    onMarkSeen: (order) {
      if (widget.store.firebaseEnabled && order.documentId.isNotEmpty) {
        unawaited(
          _persist(() => FirebaseAppService.markOrderSeen(order.documentId)),
        );
      } else {
        setState(() => order.seenByStaff = true);
        unawaited(widget.store.persistLocalData());
      }
    },
    onAddPending: _addPendingToCart,
    onRefreshPending: (product) =>
        setState(() => _refreshPendingStatuses(product)),
    onDownload: _downloadReceipt,
  );

  Widget _customersPage() => CustomersPage(
    customers: [
      ...widget.store.accounts.where(
        (account) => account.role == UserRole.customer,
      ),
      ...widget.store.manualCustomers,
    ],
    bills: widget.store.bills,
    orders: widget.store.orders,
    pendingRequests: widget.store.pendingRequests,
    onPayment: (bill, amount) {
      setState(() {
        bill.payments.add(
          PaymentEntry(
            id: 'PAY-${DateTime.now().millisecondsSinceEpoch}',
            amount: amount,
            date: DateTime.now(),
            note: 'Customer payment',
          ),
        );
      });
      if (widget.store.firebaseEnabled && bill.documentId.isNotEmpty) {
        unawaited(
          _persist(
            () => FirebaseAppService.addBillPayment(
              bill.documentId,
              <String, Object?>{
                'id': bill.payments.last.id,
                'amount': bill.payments.last.amount,
                'date': bill.payments.last.date,
                'note': bill.payments.last.note,
              },
            ),
          ),
        );
      } else {
        unawaited(widget.store.persistLocalData());
      }
    },
    onDownload: _downloadReceipt,
  );

  Widget _statisticsPage() => StatisticsPage(
    orders: widget.store.orders,
    bills: widget.store.bills,
    pendingRequests: widget.store.pendingRequests,
  );

  Widget _settingsPage() => BusinessSettingsPage(
    business: widget.store.business,
    onChanged: () {
      setState(() {});
      unawaited(
        _persist(
          () => FirebaseAppService.saveBusiness(
            name: widget.store.business.name,
            address: widget.store.business.address,
            phone: widget.store.business.phone,
          ),
        ),
      );
    },
  );

  Widget _accountPage() => AccountSettingsPage(
    account: widget.account,
    firebaseEnabled: widget.store.firebaseEnabled,
    existingLogins: widget.store.accounts
        .where((account) => account.id != widget.account.id)
        .map((account) => account.login.toLowerCase())
        .toSet(),
    onChanged: () {
      setState(() {});
      if (widget.store.firebaseEnabled && widget.account.uid != null) {
        unawaited(
          _persist(
            () => FirebaseAppService.updateMemberProfile(
              uid: widget.account.uid!,
              name: widget.account.name,
            ),
          ),
        );
      } else {
        unawaited(widget.store.persistLocalData());
      }
    },
  );

  Widget _teamPage() => TeamPage(
    accounts: widget.store.accounts,
    applications: widget.store.accountApplications,
    currentAccount: widget.account,
    onCreate: _createTeamAccount,
    onApprove: _approveAccountApplication,
    onReject: _rejectAccountApplication,
    onChanged: (account) {
      setState(() {});
      if (widget.store.firebaseEnabled && account.uid != null) {
        unawaited(
          _persist(
            () => FirebaseAppService.updateMemberProfile(
              uid: account.uid!,
              canShop: account.canShop,
              canManageStock: account.canManageStock,
              canCreateBills: account.canCreateBills,
            ),
          ),
        );
      } else {
        unawaited(widget.store.persistLocalData());
      }
    },
  );

  Future<void> _approveAccountApplication(
    AccountApplication application,
  ) async {
    await _persist(() async {
      await FirebaseAppService.approveAccountApplication(application.uid);
    });
  }

  Future<void> _rejectAccountApplication(AccountApplication application) async {
    await _persist(() async {
      await FirebaseAppService.rejectAccountApplication(application.uid);
    });
  }

  Future<void> _createTeamAccount(Account account) async {
    if (!widget.store.firebaseEnabled) {
      setState(() => widget.store.accounts.add(account));
      await widget.store.persistLocalData();
      return;
    }
    await _persist(() async {
      await FirebaseAppService.createAccount(
        accountId: account.id,
        name: account.name,
        email: account.login,
        password: account.password,
        role: account.role.name,
        canShop: account.canShop,
        canManageStock: account.canManageStock,
        canCreateBills: account.canCreateBills,
      );
    });
  }

  Future<Account?> _createWalkInCustomer(String name, String phone) async {
    final id = 'CUS-${DateTime.now().microsecondsSinceEpoch}';
    final customer = Account(
      id: id,
      name: name.trim(),
      login: '',
      password: '',
      role: UserRole.customer,
      canShop: false,
      canManageStock: false,
      canCreateBills: false,
      phone: phone.trim(),
      isWalkIn: true,
    );
    try {
      if (widget.store.firebaseEnabled) {
        await FirebaseAppService.saveManualCustomer(
          id: id,
          name: customer.name,
          phone: customer.phone,
        );
      }
      if (!widget.store.manualCustomers.any((item) => item.id == id)) {
        widget.store.manualCustomers.insert(0, customer);
      }
      if (mounted) setState(() {});
      await widget.store.persistLocalData();
      return customer;
    } catch (error) {
      if (mounted) _snack('Could not save this customer: $error');
      return null;
    }
  }

  Future<void> _assignProductionTask(
    Product product,
    Account worker,
    int piecesToMake,
  ) async {
    final id = 'TASK-${DateTime.now().microsecondsSinceEpoch}';
    final workerUid = worker.uid ?? worker.id;
    final task = ProductionTask(
      id: id,
      productId: product.id,
      productName: product.name,
      currentStock: product.stock,
      piecesToMake: piecesToMake,
      workerUid: workerUid,
      workerName: worker.name,
      assignedByName: widget.account.name,
      createdAt: DateTime.now(),
    );
    try {
      if (widget.store.firebaseEnabled) {
        if (worker.uid == null) {
          _snack('This worker account is not connected to Firebase.');
          return;
        }
        await FirebaseAppService.createProductionTask(
          id: id,
          productId: product.id,
          productName: product.name,
          currentStock: product.stock,
          piecesToMake: piecesToMake,
          workerUid: worker.uid!,
          workerName: worker.name,
          assignedByName: widget.account.name,
        );
      } else {
        widget.store.productionTasks.insert(0, task);
        await widget.store.persistLocalData();
        if (mounted) setState(() {});
      }
      if (mounted) _snack('Production task assigned to ${worker.name}.');
    } catch (error) {
      if (mounted) _snack('Could not assign production: $error');
    }
  }

  Future<void> _updateProductionTaskStatus(
    ProductionTask task,
    ProductionTaskStatus status,
  ) async {
    try {
      if (widget.store.firebaseEnabled) {
        if (task.documentId.isEmpty) {
          _snack('This task is not connected to the store database.');
          return;
        }
        await FirebaseAppService.updateProductionTaskStatus(
          taskDocumentId: task.documentId,
          status: status.name,
        );
      } else {
        setState(() => task.status = status);
        await widget.store.persistLocalData();
      }
    } catch (error) {
      if (mounted) _snack('Could not update this task: $error');
    }
  }

  void _addToCart(Product product, int pieces) {
    if (product.stock < 1) {
      _snack('This piece is currently out of stock.');
      return;
    }
    final existing = _cart[product.id];
    final next = (existing?.pieces ?? 0) + pieces;
    if (pieces > _availablePieces(product)) {
      _snack('Only ${_availablePieces(product)} pieces are available to add.');
      return;
    }
    setState(() {
      if (existing == null) {
        _cart[product.id] = CartLine(product, pieces);
      } else {
        existing.pieces = next;
      }
    });
    unawaited(_persist(() => widget.store.persistCart(widget.account)));
    _snack('$pieces ${pieces == 1 ? 'piece' : 'pieces'} added to your bag.');
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final lines = _cart.values
        .map(
          (line) => BillLine(
            productId: line.product.id,
            name: line.product.name,
            quality: line.product.quality,
            price: line.product.price,
            pieces: line.pieces,
          ),
        )
        .toList();
    for (final line in _cart.values) {
      final otherReservations = _reservedPieces(line.product) - line.pieces;
      if (line.pieces > line.product.stock - otherReservations) {
        _snack(
          'Stock changed for ${line.product.name}. Review the bag before billing.',
        );
        return;
      }
    }
    final customers = [
      ...widget.store.accounts.where(
        (account) => account.role == UserRole.customer,
      ),
      ...widget.store.manualCustomers,
    ];
    final selection = await showDialog<_CheckoutSelection>(
      context: context,
      builder: (_) => _CheckoutDialog(
        customers: customers,
        currentAccount: widget.account,
        onCreateWalkIn: _createWalkInCustomer,
      ),
    );
    if (selection == null || !mounted) return;
    final customer = selection.customer;
    if (widget.store.firebaseEnabled) {
      final customerUid = customer.isWalkIn
          ? null
          : customer.uid ??
                (widget.account.role == UserRole.customer
                    ? widget.account.uid
                    : null);
      if (customerUid == null && !customer.isWalkIn) {
        _snack('This customer account is not connected to Firebase yet.');
        return;
      }
      try {
        final result = await FirebaseAppService.placeOrder(
          customerUid: customerUid,
          manualCustomerDocumentId: customer.isWalkIn ? customer.id : null,
          paymentMode: selection.paymentMode.name,
          lines: _cart.values
              .map(
                (line) => <String, Object>{
                  'productId': line.product.id,
                  'pieces': line.pieces,
                },
              )
              .toList(),
        );
        if (!mounted) return;
        setState(() {
          _cart.clear();
          _page = _Page.orders;
        });
        await _fulfillPendingRequests(customer, lines);
        _snack('Order ${result['orderId']} placed successfully.');
      } on FirebaseFunctionsException catch (error) {
        if (mounted) _snack(error.message ?? 'Could not place the order.');
      } catch (error) {
        if (mounted) _snack('Could not place the order: $error');
      }
      return;
    }
    final now = DateTime.now();
    final billNumber = (widget.store.bills.length + 1).toString().padLeft(
      4,
      '0',
    );
    final billId = 'PJ-${now.year}-$billNumber';
    final payments = selection.paymentMode == PaymentMode.cash
        ? [
            PaymentEntry(
              id: 'PAY-${now.millisecondsSinceEpoch}',
              amount: lines.fold(0, (sum, line) => sum + line.total),
              date: now,
              note: 'Cash at order',
            ),
          ]
        : <PaymentEntry>[];
    setState(() {
      final purchasedProducts = _cart.values
          .map((line) => line.product)
          .toList();
      for (final line in _cart.values) {
        line.product.stock -= line.pieces;
      }
      widget.store.bills.insert(
        0,
        Bill(
          id: billId,
          customer: customer.name,
          customerId: customer.id,
          customerUid: customer.uid ?? '',
          createdAt: now,
          lines: lines,
          paymentMode: selection.paymentMode,
          payments: payments,
          createdByName: widget.account.name,
        ),
      );
      widget.store.orders.insert(
        0,
        CustomerOrder(
          id: 'ORD-${now.millisecondsSinceEpoch}',
          customerId: customer.id,
          customerName: customer.name,
          customerUid: customer.uid ?? '',
          createdAt: now,
          billId: billId,
          lines: lines,
          placedByName: widget.account.name,
        )..seenByStaff = widget.account.role != UserRole.customer,
      );
      _cart.clear();
      for (final product in purchasedProducts) {
        _refreshPendingStatuses(product);
      }
      _page = _Page.orders;
    });
    await widget.store.persistLocalData();
    await _fulfillPendingRequests(customer, lines);
    _snack('Order placed. Staff can see it in the orders inbox.');
  }

  Future<void> _fulfillPendingRequests(
    Account customer,
    List<BillLine> purchasedLines,
  ) async {
    final purchased = <String, int>{};
    for (final line in purchasedLines) {
      purchased.update(
        line.productId,
        (pieces) => pieces + line.pieces,
        ifAbsent: () => line.pieces,
      );
    }
    final requests =
        widget.store.pendingRequests
            .where(
              (request) =>
                  request.customerId == customer.id &&
                  request.status == PendingStatus.ready,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var changed = false;
    for (final request in requests) {
      final remaining = purchased[request.productId] ?? 0;
      if (remaining < request.pieces) continue;
      purchased[request.productId] = remaining - request.pieces;
      if (widget.store.firebaseEnabled && request.documentId.isNotEmpty) {
        try {
          await FirebaseAppService.updatePendingStatus(
            request.documentId,
            PendingStatus.fulfilled.name,
          );
        } catch (error) {
          if (mounted) {
            _snack(
              'The order was placed, but a pending item did not sync: $error',
            );
          }
          continue;
        }
      }
      request.status = PendingStatus.fulfilled;
      changed = true;
    }
    if (changed && mounted) {
      setState(() {});
      await widget.store.persistLocalData();
    }
  }

  Future<void> _requestPending(Product product) async {
    final customers = widget.store.accounts
        .where((account) => account.role == UserRole.customer)
        .toList();
    if (widget.account.role != UserRole.customer && customers.isEmpty) {
      _snack('Ask an administrator to create a customer account first.');
      return;
    }
    final request = await showDialog<_PendingDraft>(
      context: context,
      builder: (_) => _PendingRequestDialog(
        product: product,
        customers: customers,
        currentAccount: widget.account,
      ),
    );
    if (request == null || !mounted) return;
    if (widget.store.firebaseEnabled) {
      final customerUid =
          request.customer.uid ??
          (widget.account.role == UserRole.customer
              ? widget.account.uid
              : null);
      if (customerUid == null) {
        _snack('This customer account is not connected to Firebase yet.');
        return;
      }
      await _persist(
        () => FirebaseAppService.savePendingRequest(
          id: 'PEN-${DateTime.now().millisecondsSinceEpoch}',
          customerUid: customerUid,
          customerId: request.customer.id,
          customerName: request.customer.name,
          productId: product.id,
          productName: product.name,
          quality: product.quality,
          pricePerPiece: product.price,
          pieces: request.pieces,
        ),
      );
      if (mounted) {
        setState(
          () => _page = widget.account.role == UserRole.customer
              ? _Page.pending
              : _Page.orders,
        );
      }
      return;
    }
    setState(() {
      widget.store.pendingRequests.add(
        PendingRequest(
          id: 'PEN-${DateTime.now().millisecondsSinceEpoch}',
          customerId: request.customer.id,
          customerName: request.customer.name,
          productId: product.id,
          productName: product.name,
          quality: product.quality,
          pricePerPiece: product.price,
          pieces: request.pieces,
          createdAt: DateTime.now(),
        ),
      );
      _page = widget.account.role == UserRole.customer
          ? _Page.pending
          : _Page.orders;
    });
    _snack('Unavailable item saved as a pending request, not a bill.');
  }

  void _refreshPendingStatuses(Product product) {
    if (widget.store.firebaseEnabled &&
        (widget.account.role == UserRole.customer ||
            (!_canManageStock && !_canCreateBills))) {
      return;
    }
    var available = product.stock - _reservedPieces(product);
    var changedLocally = false;
    final requests =
        widget.store.pendingRequests
            .where(
              (request) =>
                  request.productId == product.id &&
                  request.status == PendingStatus.pending,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final request in requests) {
      if (available >= request.pieces) {
        request.status = PendingStatus.ready;
        changedLocally = true;
        available -= request.pieces;
        if (widget.store.firebaseEnabled &&
            widget.account.role != UserRole.customer &&
            request.documentId.isNotEmpty) {
          unawaited(
            _persist(
              () => FirebaseAppService.updatePendingStatus(
                request.documentId,
                request.status.name,
              ),
            ),
          );
        }
      }
    }
    if (changedLocally && !widget.store.firebaseEnabled) {
      unawaited(widget.store.persistLocalData());
    }
  }

  void _addPendingToCart(PendingRequest request) {
    Product? product;
    for (final item in widget.store.products) {
      if (item.id == request.productId) {
        product = item;
        break;
      }
    }
    if (product == null || _availablePieces(product) < request.pieces) {
      _snack('Stock is not available yet.');
      return;
    }
    _addToCart(product, request.pieces);
  }

  Future<void> _editBillLineQuantity(Bill bill, int lineIndex) async {
    final line = bill.lines[lineIndex];
    final pieces = await showDialog<int>(
      context: context,
      builder: (_) => _EditBillLineQuantityDialog(line: line),
    );
    if (pieces == null || !mounted || pieces == line.pieces) return;
    final newTotal = bill.total + (pieces - line.pieces) * line.price;
    if (bill.paid > newTotal + .001) {
      _snack(
        'The new bill total cannot be lower than the amount already paid.',
      );
      return;
    }
    if (widget.store.firebaseEnabled) {
      if (bill.documentId.isEmpty) {
        _snack('This bill is not connected to the store database.');
        return;
      }
      try {
        await FirebaseAppService.updateBillLineQuantity(
          billDocumentId: bill.documentId,
          lineIndex: lineIndex,
          pieces: pieces,
        );
        if (mounted) {
          final remaining = line.orderedPieces - pieces;
          _snack(
            remaining > 0
                ? '$remaining ${remaining == 1 ? 'piece' : 'pieces'} moved to pending items.'
                : 'Bill quantity updated.',
          );
        }
      } on FirebaseFunctionsException catch (error) {
        if (mounted) _snack(error.message ?? 'Could not update bill quantity.');
      } catch (error) {
        if (mounted) _snack('Could not update bill quantity: $error');
      }
      return;
    }

    Product? product;
    for (final candidate in widget.store.products) {
      if (candidate.id == line.productId) {
        product = candidate;
        break;
      }
    }
    if (product == null) {
      _snack(
        'This product is missing from inventory, so stock cannot be reconciled.',
      );
      return;
    }
    final stockChange = line.pieces - pieces;
    if (stockChange < 0 && product.stock < -stockChange) {
      _snack('There is not enough stock to increase this bill quantity.');
      return;
    }
    final pendingId = 'bill-${bill.id}-$lineIndex';
    final pendingIndex = widget.store.pendingRequests.indexWhere(
      (request) => request.id == pendingId,
    );
    if (pendingIndex >= 0 &&
        widget.store.pendingRequests[pendingIndex].status ==
            PendingStatus.fulfilled) {
      _snack(
        'This pending quantity was already fulfilled. Edit its follow-up sale instead.',
      );
      return;
    }
    final remaining = line.orderedPieces - pieces;
    final now = DateTime.now();
    setState(() {
      product!.stock += stockChange;
      bill.lines[lineIndex] = BillLine(
        productId: line.productId,
        name: line.name,
        quality: line.quality,
        price: line.price,
        pieces: pieces,
        orderedPieces: line.orderedPieces,
      );
      for (final order in widget.store.orders.where(
        (order) => order.billId == bill.id,
      )) {
        final orderLineIndex = order.lines.indexWhere(
          (orderLine) => orderLine.productId == line.productId,
        );
        if (orderLineIndex >= 0) {
          order.lines[orderLineIndex] = BillLine(
            productId: line.productId,
            name: line.name,
            quality: line.quality,
            price: line.price,
            pieces: pieces,
            orderedPieces: line.orderedPieces,
          );
        }
      }
      if (remaining > 0) {
        final request = PendingRequest(
          id: pendingId,
          customerId: bill.customerId,
          customerName: bill.customer,
          productId: line.productId,
          productName: line.name,
          quality: line.quality,
          pricePerPiece: line.price,
          pieces: remaining,
          createdAt: pendingIndex >= 0
              ? widget.store.pendingRequests[pendingIndex].createdAt
              : now,
          customerUid: bill.customerUid,
        );
        if (pendingIndex >= 0) {
          widget.store.pendingRequests[pendingIndex] = request;
        } else {
          widget.store.pendingRequests.add(request);
        }
      } else if (pendingIndex >= 0) {
        widget.store.pendingRequests.removeAt(pendingIndex);
      }
      _refreshPendingStatuses(product);
    });
    await widget.store.persistLocalData();
    _snack(
      remaining > 0
          ? '$remaining ${remaining == 1 ? 'piece' : 'pieces'} moved to pending items.'
          : 'Bill quantity updated.',
    );
  }

  Future<void> _editBillLinePrice(Bill bill, int lineIndex) async {
    final currentLine = bill.lines[lineIndex];
    final price = await showDialog<double>(
      context: context,
      builder: (_) => _EditBillLinePriceDialog(line: currentLine),
    );
    if (price == null || !mounted) return;
    if (widget.store.firebaseEnabled) {
      if (bill.documentId.isEmpty) {
        _snack('This bill is not connected to the store database.');
        return;
      }
      try {
        await FirebaseAppService.updateBillLinePrice(
          billDocumentId: bill.documentId,
          lineIndex: lineIndex,
          price: price,
        );
      } on FirebaseFunctionsException catch (error) {
        _snack(error.message ?? 'Could not update this bill price.');
        return;
      } catch (error) {
        _snack('Could not update this bill price: $error');
        return;
      }
    }
    setState(() {
      bill.lines[lineIndex] = BillLine(
        productId: currentLine.productId,
        name: currentLine.name,
        quality: currentLine.quality,
        price: price,
        pieces: currentLine.pieces,
        orderedPieces: currentLine.orderedPieces,
      );
    });
    await widget.store.persistLocalData();
  }

  Future<void> _persist(Future<void> Function() operation) async {
    if (!widget.store.firebaseEnabled) {
      try {
        await widget.store.persistLocalData();
      } catch (error) {
        if (mounted) _snack('Could not save this change: $error');
      }
      return;
    }
    try {
      await operation();
    } catch (error) {
      if (mounted) _snack('Could not sync this change: $error');
    }
  }

  Future<void> _downloadReceipt(Bill bill) async {
    try {
      final document = _createReceiptPdf(widget.store.business, bill);
      final bytes = await document.save();
      final result = await FilePicker.saveFile(
        fileName: '${bill.id}.pdf',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (mounted) {
        _snack(
          result == null ? 'Receipt save was cancelled.' : 'Receipt saved.',
        );
      }
    } catch (error) {
      if (mounted) _snack('Could not save receipt: $error');
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Arial')),
      ),
    );
}

class _ShopHero extends StatelessWidget {
  const _ShopHero({required this.name, required this.productCount});
  final String name;
  final int productCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 206,
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF282621), Color(0xFF5B4B35), Color(0xFF937342)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 5,
            top: -28,
            child: Icon(
              Icons.auto_awesome,
              size: 220,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _Overline('CURATED FOR YOU', light: true),
              const SizedBox(height: 12),
              Text(
                'A little brilliance, ${name.split(' ').first}.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 31),
              ),
              const SizedBox(height: 8),
              Text(
                '$productCount considered pieces · Individually priced',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .74),
                  fontFamily: 'Arial',
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Positioned(right: 0, bottom: 0, child: _GoldSeal()),
        ],
      ),
    );
  }
}

class _GoldSeal extends StatelessWidget {
  const _GoldSeal();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: Colors.white.withValues(alpha: .25)),
    ),
    child: const Text(
      'CRAFTED WITH CARE',
      style: TextStyle(
        fontFamily: 'Arial',
        color: Colors.white,
        fontSize: 9,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.allowCart,
    required this.availablePieces,
    required this.onAdd,
    required this.onRequestPending,
    required this.onOpenDetails,
  });
  final Product product;
  final bool allowCart;
  final int availablePieces;
  final ValueChanged<int> onAdd;
  final VoidCallback onRequestPending;
  final VoidCallback onOpenDetails;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  int _pieces = 1;

  @override
  void didUpdateWidget(covariant ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.availablePieces > 0 && _pieces > widget.availablePieces) {
      _pieces = widget.availablePieces;
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return GestureDetector(
      onTap: widget.onOpenDetails,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    url: product.imageUrl,
                    id: product.id,
                    bytes: product.imageBytes,
                  ),
                  Positioned(
                    left: 13,
                    top: 13,
                    child: _Badge(text: product.category.toUpperCase()),
                  ),
                  Positioned(
                    right: 13,
                    top: 13,
                    child: _Badge(
                      text: widget.availablePieces > 0
                          ? '${widget.availablePieces} PIECES'
                          : 'OUT OF STOCK',
                      muted: widget.availablePieces == 0,
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 17,
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.quality,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontFamily: 'Arial',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        product.id,
                        style: const TextStyle(
                          color: _muted,
                          fontFamily: 'Arial',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontFamily: 'Arial',
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(product.price),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Price per piece',
                    style: TextStyle(
                      color: _muted,
                      fontFamily: 'Arial',
                      fontSize: 10,
                    ),
                  ),
                  if (widget.allowCart) ...[
                    const SizedBox(height: 12),
                    if (widget.availablePieces > 0)
                      Row(
                        children: [
                          _PieceQuantityPicker(
                            pieces: _pieces,
                            maximum: widget.availablePieces,
                            onChanged: (pieces) =>
                                setState(() => _pieces = pieces),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => widget.onAdd(_pieces),
                            icon: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 16,
                            ),
                            label: const Text('Add to bag'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _ink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              textStyle: const TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (widget.availablePieces == 0)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onRequestPending,
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                          ),
                          label: const Text('Request when available'),
                        ),
                      )
                    else
                      const Text(
                        'All remaining pieces are reserved in bags.',
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailsPage extends StatefulWidget {
  const _ProductDetailsPage({
    required this.product,
    required this.allowCart,
    required this.availablePieces,
    required this.onAdd,
    required this.onRequestPending,
  });

  final Product product;
  final bool allowCart;
  final int availablePieces;
  final ValueChanged<int> onAdd;
  final VoidCallback onRequestPending;

  @override
  State<_ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<_ProductDetailsPage> {
  int _pieces = 1;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final inStock = widget.availablePieces > 0;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: ProductImage(
          url: product.imageUrl,
          id: product.id,
          bytes: product.imageBytes,
        ),
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Badge(text: product.category.toUpperCase()),
        const SizedBox(height: 16),
        Text(product.name, style: const TextStyle(fontSize: 32, height: 1.15)),
        const SizedBox(height: 10),
        Text(
          product.quality,
          style: const TextStyle(
            color: _muted,
            fontFamily: 'Arial',
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _money(product.price),
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
        ),
        const Text(
          'Price per piece',
          style: TextStyle(color: _muted, fontFamily: 'Arial', fontSize: 12),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MiniMetric(label: 'PRODUCT ID', value: product.id),
            _MiniMetric(
              label: 'AVAILABLE',
              value: inStock
                  ? '${widget.availablePieces} pieces'
                  : 'Out of stock',
              emphasis: !inStock,
            ),
          ],
        ),
        if (product.description.trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('About this piece', style: TextStyle(fontSize: 19)),
          const SizedBox(height: 8),
          Text(
            product.description,
            style: const TextStyle(
              color: _muted,
              fontFamily: 'Arial',
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
        if (widget.allowCart) ...[
          const SizedBox(height: 26),
          if (inStock)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _PieceQuantityPicker(
                  pieces: _pieces,
                  maximum: widget.availablePieces,
                  onChanged: (pieces) => setState(() => _pieces = pieces),
                ),
                FilledButton.icon(
                  onPressed: () {
                    widget.onAdd(_pieces);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: const Text('Add to bag'),
                ),
              ],
            )
          else if (!inStock)
            OutlinedButton.icon(
              onPressed: widget.onRequestPending,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Request when available'),
            )
          else
            const Text(
              'All remaining pieces are reserved in bags.',
              style: TextStyle(
                color: _muted,
                fontFamily: 'Arial',
                fontSize: 12,
              ),
            ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        title: const Text('Piece details'),
        backgroundColor: _paper,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: image),
                            const SizedBox(width: 40),
                            Expanded(child: details),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            image,
                            const SizedBox(height: 26),
                            details,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PieceQuantityPicker extends StatelessWidget {
  const _PieceQuantityPicker({
    required this.pieces,
    required this.maximum,
    required this.onChanged,
  });
  final int pieces;
  final int maximum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(
      color: _paper,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyButton(
          icon: Icons.remove,
          onPressed: pieces > 1 ? () => onChanged(pieces - 1) : null,
        ),
        Text(
          '$pieces',
          style: const TextStyle(
            fontFamily: 'Arial',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        _QtyButton(
          icon: Icons.add,
          onPressed: pieces < maximum ? () => onChanged(pieces + 1) : null,
        ),
      ],
    ),
  );
}

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    required this.id,
    this.bytes,
  });
  final String url;
  final String id;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(
        bytes!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    if (url.trim().isEmpty) return _placeholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              fit: StackFit.expand,
              children: [
                _placeholder(),
                const Center(
                  child: CircularProgressIndicator(
                    color: _gold,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _placeholder() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFECE5D9), Color(0xFFCFC2AA)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 54,
            color: _gold.withValues(alpha: .65),
          ),
          const SizedBox(height: 11),
          Text(
            id,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'Arial',
              color: _muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.muted = false});
  final String text;
  final bool muted;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: muted ? const Color(0xDD6C665B) : const Color(0xDDFBF8F1),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: muted ? Colors.white : _ink,
        fontSize: 9,
        fontFamily: 'Arial',
        letterSpacing: .7,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class InventoryPage extends StatelessWidget {
  const InventoryPage({
    super.key,
    required this.products,
    required this.categories,
    required this.pendingRequests,
    required this.onCategoryAdded,
    required this.onChanged,
  });
  final List<Product> products;
  final Set<String> categories;
  final List<PendingRequest> pendingRequests;
  final ValueChanged<String> onCategoryAdded;
  final ValueChanged<Product> onChanged;

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'STOCKROOM',
    title: 'Product inventory',
    description: 'Keep per-piece prices and physical piece counts up to date.',
    action: FilledButton.icon(
      onPressed: () => _showProductForm(context),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add product'),
    ),
    child: products.isEmpty
        ? const _EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Your inventory is empty',
            text: 'Add a product to start your collection.',
          )
        : Column(
            children: products
                .map(
                  (product) => _ProductRow(
                    product: product,
                    pendingRequests: pendingRequests
                        .where((request) => request.productId == product.id)
                        .toList(),
                    onChanged: () => onChanged(product),
                    onEdit: () => _showProductForm(context, product: product),
                  ),
                )
                .toList(),
          ),
  );

  Future<void> _showProductForm(
    BuildContext context, {
    Product? product,
  }) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductForm(
        product: product,
        existingIds: products.map((p) => p.id).toSet(),
        categories: categories,
        onCategoryAdded: onCategoryAdded,
      ),
    );
    if (result == null) return;
    if (product == null) {
      products.add(result);
    } else {
      product.name = result.name;
      product.quality = result.quality;
      product.price = result.price;
      product.stock = result.stock;
      product.imageUrl = result.imageUrl;
      product.imageBytes = result.imageBytes;
      product.description = result.description;
      product.category = result.category;
    }
    onChanged(product ?? result);
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.pendingRequests,
    required this.onChanged,
    required this.onEdit,
  });
  final Product product;
  final List<PendingRequest> pendingRequests;
  final VoidCallback onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final openRequests = pendingRequests
        .where((request) => request.status != PendingStatus.fulfilled)
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox(
              width: 76,
              height: 76,
              child: ProductImage(
                url: product.imageUrl,
                id: product.id,
                bytes: product.imageBytes,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.id}  ·  ${product.quality}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontFamily: 'Arial',
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      '${_money(product.price)} / piece',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${product.stock} pieces in stock',
                      style: const TextStyle(
                        color: _muted,
                        fontFamily: 'Arial',
                        fontSize: 12,
                      ),
                    ),
                    if (openRequests > 0)
                      Text(
                        '$openRequests customer requests',
                        style: const TextStyle(
                          color: _gold,
                          fontFamily: 'Arial',
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit product',
            icon: const Icon(Icons.edit_outlined, color: _muted),
          ),
          PopupMenuButton<String>(
            tooltip: 'Update stock',
            onSelected: (choice) {
              final amount = int.tryParse(choice.substring(1)) ?? 0;
              product.stock = choice.startsWith('+')
                  ? product.stock + amount
                  : (product.stock - amount).clamp(0, 999999).toInt();
              onChanged();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: '+1', child: Text('Add 1 piece')),
              PopupMenuItem(value: '+5', child: Text('Add 5 pieces')),
              PopupMenuItem(value: '-1', child: Text('Remove 1 piece')),
            ],
            icon: const Icon(Icons.add_box_outlined, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({
    this.product,
    required this.existingIds,
    required this.categories,
    required this.onCategoryAdded,
  });
  final Product? product;
  final Set<String> existingIds;
  final Set<String> categories;
  final ValueChanged<String> onCategoryAdded;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _quality;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _image;
  late final TextEditingController _description;
  late final Set<String> _categories;
  Uint8List? _imageBytes;
  late String _category;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _categories = Set<String>.from(widget.categories);
    _imageBytes = p?.imageBytes;
    _id = TextEditingController(text: p?.id ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _quality = TextEditingController(text: p?.quality ?? '');
    _price = TextEditingController(
      text: p == null ? '' : p.price.toStringAsFixed(0),
    );
    _stock = TextEditingController(text: p?.stock.toString() ?? '');
    _image = TextEditingController(text: p?.imageUrl ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _category =
        p?.category ?? (_categories.isEmpty ? 'General' : _categories.first);
    _categories.add(_category);
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _quality.dispose();
    _price.dispose();
    _stock.dispose();
    _image.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 570, maxHeight: 780),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product == null ? 'Add a product' : 'Edit product',
              style: const TextStyle(fontSize: 25),
            ),
            const SizedBox(height: 5),
            const Text(
              'Add an item with its per-piece price, stock count, and product photo.',
              style: TextStyle(
                color: _muted,
                fontFamily: 'Arial',
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    _field(
                      _id,
                      'Product ID',
                      required: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a product ID';
                        }
                        final id = value.trim().toUpperCase();
                        if (widget.existingIds.contains(id) &&
                            id != widget.product?.id) {
                          return 'This product ID is already in use';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _field(_name, 'Product name', required: true),
                    const SizedBox(height: 12),
                    _field(
                      _quality,
                      'Quality / material',
                      hint: 'e.g. 18K gold · Hallmarked',
                      required: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            _price,
                            'Price per piece',
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            required: true,
                            validator: (v) =>
                                double.tryParse(v ?? '') == null ||
                                    double.parse(v!) <= 0
                                ? 'Enter a valid price'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            _stock,
                            'Stock (pieces)',
                            keyboard: TextInputType.number,
                            required: true,
                            validator: (v) =>
                                int.tryParse(v ?? '') == null ||
                                    int.parse(v!) < 0
                                ? 'Enter a valid stock count'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _category,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: (_categories.toList()..sort())
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _category = value ?? _category),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Add category',
                          onPressed: _addCategory,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field(
                      _image,
                      'Photo URL (optional)',
                      hint: 'Or choose a photo file below',
                      onChanged: (value) => setState(() {
                        if (value.trim().isNotEmpty) _imageBytes = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from gallery or files'),
                    ),
                    if (_imageBytes != null ||
                        _image.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 120,
                          child: ProductImage(
                            url: _image.text,
                            id: _id.text,
                            bytes: _imageBytes,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _field(_description, 'Description', maxLines: 2),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 9),
                FilledButton(
                  onPressed: _save,
                  child: Text(
                    widget.product == null ? 'Save product' : 'Save changes',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickPhoto() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _image.clear();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open photo: $error')));
      }
    }
  }

  Future<void> _addCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewCategoryDialog(categories: _categories),
    );
    if (name == null || !mounted) return;
    final normalized = name.trim();
    if (_categories.any(
      (item) => item.toLowerCase() == normalized.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That category already exists.')),
      );
      return;
    }
    setState(() {
      _categories.add(normalized);
      _category = normalized;
    });
    widget.onCategoryAdded(normalized);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    maxLines: maxLines,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator:
        validator ??
        (required
            ? (v) => v == null || v.trim().isEmpty ? 'Enter $label' : null
            : null),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Product(
        id: _id.text.trim().toUpperCase(),
        name: _name.text.trim(),
        quality: _quality.text.trim(),
        price: double.parse(_price.text),
        stock: int.parse(_stock.text),
        imageUrl: _image.text.trim(),
        imageBytes: _imageBytes,
        description: _description.text.trim(),
        category: _category,
        createdAt: widget.product?.createdAt,
      ),
    );
  }
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog({required this.categories});
  final Set<String> categories;

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Add a category'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Category name'),
        validator: (value) {
          final name = value?.trim() ?? '';
          if (name.isEmpty) return 'Enter a category name';
          if (widget.categories.any(
            (item) => item.toLowerCase() == name.toLowerCase(),
          )) {
            return 'This category already exists';
          }
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, _controller.text.trim());
        },
        child: const Text('Add category'),
      ),
    ],
  );
}

class CartPage extends StatelessWidget {
  const CartPage({
    super.key,
    required this.cart,
    required this.onChanged,
    required this.onCheckout,
    required this.allowOrdering,
  });
  final Map<String, CartLine> cart;
  final VoidCallback onChanged;
  final VoidCallback onCheckout;
  final bool allowOrdering;

  @override
  Widget build(BuildContext context) {
    final lines = cart.values.toList();
    final total = lines.fold<double>(0, (sum, line) => sum + line.total);
    return _PageFrame(
      eyebrow: 'YOUR SELECTION',
      title: 'Your bag',
      description:
          '${lines.fold<int>(0, (sum, line) => sum + line.pieces)} pieces selected',
      child: lines.isEmpty
          ? const _EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your bag is waiting',
              text: 'Add a piece from the collection to see it here.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...lines.map(
                  (line) => _CartLineCard(line: line, onChanged: onChanged),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Subtotal', value: _money(total)),
                      const SizedBox(height: 13),
                      const Divider(color: _line),
                      const SizedBox(height: 9),
                      _SummaryRow(
                        label: 'Total',
                        value: _money(total),
                        strong: true,
                      ),
                      const SizedBox(height: 17),
                      SizedBox(
                        width: double.infinity,
                        height: 49,
                        child: FilledButton.icon(
                          onPressed: allowOrdering ? onCheckout : null,
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                          ),
                          label: const Text('Place order'),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        allowOrdering
                            ? 'Placing the order creates an invoice and deducts pieces from stock.'
                            : 'You need order permission to place an order.',
                        style: TextStyle(
                          color: _muted,
                          fontFamily: 'Arial',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({required this.line, required this.onChanged});
  final CartLine line;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 500;
      final image = ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: compact ? 62 : 76,
          height: compact ? 62 : 76,
          child: ProductImage(
            url: line.product.imageUrl,
            id: line.product.id,
            bytes: line.product.imageBytes,
          ),
        ),
      );
      final details = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${line.product.id} · ${line.product.quality}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${_money(line.product.price)} / piece',
              style: const TextStyle(
                fontFamily: 'Arial',
                fontSize: 11,
                color: _muted,
              ),
            ),
          ],
        ),
      );
      final quantity = _QuantityControl(line: line, onChanged: onChanged);
      final total = Text(
        _money(line.total),
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );
      return Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: compact
            ? Column(
                children: [
                  Row(children: [image, const SizedBox(width: 12), details]),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      const Spacer(),
                      quantity,
                      const SizedBox(width: 10),
                      total,
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  image,
                  const SizedBox(width: 14),
                  details,
                  quantity,
                  const SizedBox(width: 10),
                  SizedBox(width: 82, child: total),
                ],
              ),
      );
    },
  );
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({required this.line, required this.onChanged});
  final CartLine line;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_ShopShellState>();
    final canAdd = shell == null
        ? line.pieces < line.product.stock
        : shell._availablePieces(line.product) > 0;
    return Container(
      decoration: BoxDecoration(
        color: _paper,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyButton(
            icon: Icons.remove,
            onPressed: () {
              if (line.pieces <= 1) {
                final state = context
                    .findAncestorStateOfType<_ShopShellState>();
                state?.widget.store
                    .cartFor(state.widget.account)
                    .remove(line.product.id);
              } else {
                line.pieces--;
              }
              onChanged();
            },
          ),
          Text(
            '${line.pieces}',
            style: const TextStyle(
              fontFamily: 'Arial',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          _QtyButton(
            icon: Icons.add,
            onPressed: canAdd
                ? () {
                    line.pieces++;
                    onChanged();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    padding: EdgeInsets.zero,
    icon: Icon(icon, color: onPressed == null ? _line : _ink),
  );
}

class _CheckoutSelection {
  const _CheckoutSelection({required this.customer, required this.paymentMode});
  final Account customer;
  final PaymentMode paymentMode;
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({
    required this.customers,
    required this.currentAccount,
    required this.onCreateWalkIn,
  });
  final List<Account> customers;
  final Account currentAccount;
  final Future<Account?> Function(String name, String phone) onCreateWalkIn;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late final List<Account> _customers = List<Account>.of(widget.customers);
  late Account? _selected = widget.currentAccount.role == UserRole.customer
      ? widget.currentAccount
      : (_customers.isEmpty ? null : _customers.first);
  PaymentMode _paymentMode = PaymentMode.cash;

  Future<void> _addWalkInCustomer() async {
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _WalkInCustomerDialog(),
    );
    if (details == null || !mounted) return;
    final customer = await widget.onCreateWalkIn(
      details['name'] ?? '',
      details['phone'] ?? '',
    );
    if (!mounted || customer == null) return;
    setState(() {
      _customers.insert(0, customer);
      _selected = customer;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Place this order'),
    content: SizedBox(
      width: 390,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.currentAccount.role != UserRole.customer) ...[
            if (_customers.isNotEmpty)
              DropdownButtonFormField<Account>(
                initialValue: _selected,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: _customers
                    .map(
                      (customer) => DropdownMenuItem(
                        value: customer,
                        child: Text(
                          '${customer.name}${customer.phone.isEmpty ? '' : ' ? ${customer.phone}'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (customer) => setState(() => _selected = customer),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No saved customers yet. Add the walk-in customer for this sale.',
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addWalkInCustomer,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add walk-in customer'),
              ),
            ),
            const SizedBox(height: 15),
          ],
          if (widget.currentAccount.role == UserRole.customer) ...[
            const Text(
              'Payment will be recorded by the store',
              style: TextStyle(
                fontFamily: 'Arial',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Your bill will show the amount due. The owner can record payment after it is received.',
              style: TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ] else ...[
            const Text(
              'Payment type',
              style: TextStyle(
                fontFamily: 'Arial',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<PaymentMode>(
              segments: const [
                ButtonSegment(
                  value: PaymentMode.cash,
                  label: Text('Cash'),
                  icon: Icon(Icons.payments_outlined),
                ),
                ButtonSegment(
                  value: PaymentMode.credit,
                  label: Text('Credit'),
                  icon: Icon(Icons.schedule_outlined),
                ),
              ],
              selected: {_paymentMode},
              onSelectionChanged: (selection) =>
                  setState(() => _paymentMode = selection.first),
            ),
            const SizedBox(height: 9),
            Text(
              _paymentMode == PaymentMode.cash
                  ? 'Cash marks this order as fully paid.'
                  : 'Credit records the full amount as due. The owner can record payments later.',
              style: const TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected == null
            ? null
            : () => Navigator.pop(
                context,
                _CheckoutSelection(
                  customer: _selected!,
                  paymentMode: widget.currentAccount.role == UserRole.customer
                      ? PaymentMode.credit
                      : _paymentMode,
                ),
              ),
        child: const Text('Place order'),
      ),
    ],
  );
}

class _WalkInCustomerDialog extends StatefulWidget {
  const _WalkInCustomerDialog();

  @override
  State<_WalkInCustomerDialog> createState() => _WalkInCustomerDialogState();
}

class _WalkInCustomerDialogState extends State<_WalkInCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save customer'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Customer name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter the customer name'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': _name.text.trim(),
            'phone': _phone.text.trim(),
          });
        },
        child: const Text('Save customer'),
      ),
    ],
  );
}

class ProductionTasksPage extends StatelessWidget {
  const ProductionTasksPage({
    super.key,
    required this.account,
    required this.tasks,
    required this.products,
    required this.workers,
    required this.canAssign,
    required this.onAssign,
    required this.onStatusChanged,
  });
  final Account account;
  final List<ProductionTask> tasks;
  final List<Product> products;
  final List<Account> workers;
  final bool canAssign;
  final Future<void> Function(Product, Account, int) onAssign;
  final Future<void> Function(ProductionTask, ProductionTaskStatus)
  onStatusChanged;

  Future<void> _showAssignmentDialog(BuildContext context) async {
    final assignment = await showDialog<_ProductionDraft>(
      context: context,
      builder: (_) =>
          _ProductionAssignmentDialog(products: products, workers: workers),
    );
    if (assignment != null) {
      await onAssign(assignment.product, assignment.worker, assignment.pieces);
    }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'WORKSHOP',
    title: account.role == UserRole.employee
        ? 'My production tasks'
        : 'Production tasks',
    description: 'Workers see the product, current stock, and requested quantity assigned by the store team.',
    action: canAssign
        ? FilledButton.icon(
            onPressed: products.isEmpty || workers.isEmpty
                ? null
                : () => _showAssignmentDialog(context),
            icon: const Icon(Icons.add_task, size: 18),
            label: const Text('Assign work'),
          )
        : null,
    child: tasks.isEmpty
        ? _EmptyState(
            icon: Icons.precision_manufacturing_outlined,
            title: canAssign ? 'No production tasks yet' : 'No work assigned',
            text: canAssign
                ? 'Assign a product and quantity to a worker when stock needs replenishing.'
                : 'New tasks from the owner or admin will appear here with the current stock count.',
          )
        : Column(
            children: tasks.map((task) {
              final nextStatus = switch (task.status) {
                ProductionTaskStatus.assigned =>
                  ProductionTaskStatus.inProgress,
                ProductionTaskStatus.inProgress =>
                  ProductionTaskStatus.completed,
                ProductionTaskStatus.completed => null,
              };
              final actionLabel = task.status == ProductionTaskStatus.assigned
                  ? 'Start work'
                  : 'Mark complete';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.productName,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4EFE3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _productionStatusLabel(task.status),
                            style: const TextStyle(
                              fontFamily: 'Arial',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Product ${task.productId} · Stock when assigned: ${task.currentStock} · Make: ${task.piecesToMake}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Assigned to ${task.workerName} by ${task.assignedByName}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        fontSize: 11,
                      ),
                    ),
                    if (nextStatus != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => onStatusChanged(task, nextStatus),
                          icon: Icon(
                            task.status == ProductionTaskStatus.assigned
                                ? Icons.play_arrow
                                : Icons.done_all,
                          ),
                          label: Text(actionLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
  );
}

String _productionStatusLabel(ProductionTaskStatus status) => switch (status) {
  ProductionTaskStatus.assigned => 'Assigned',
  ProductionTaskStatus.inProgress => 'In progress',
  ProductionTaskStatus.completed => 'Completed',
};

class _ProductionDraft {
  const _ProductionDraft({
    required this.product,
    required this.worker,
    required this.pieces,
  });
  final Product product;
  final Account worker;
  final int pieces;
}

class _ProductionAssignmentDialog extends StatefulWidget {
  const _ProductionAssignmentDialog({
    required this.products,
    required this.workers,
  });
  final List<Product> products;
  final List<Account> workers;

  @override
  State<_ProductionAssignmentDialog> createState() =>
      _ProductionAssignmentDialogState();
}

class _ProductionAssignmentDialogState
    extends State<_ProductionAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pieces = TextEditingController(text: '1');
  late Product? _product = widget.products.isEmpty
      ? null
      : widget.products.first;
  late Account? _worker = widget.workers.isEmpty ? null : widget.workers.first;

  @override
  void dispose() {
    _pieces.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Assign production'),
    content: SizedBox(
      width: 390,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<Product>(
              initialValue: _product,
              decoration: const InputDecoration(labelText: 'Product'),
              items: widget.products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product,
                      child: Text(
                        '${product.name} · stock ${product.stock}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (product) => setState(() => _product = product),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Account>(
              initialValue: _worker,
              decoration: const InputDecoration(labelText: 'Worker'),
              items: widget.workers
                  .map(
                    (worker) => DropdownMenuItem(
                      value: worker,
                      child: Text(worker.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (worker) => setState(() => _worker = worker),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pieces,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pieces to make'),
              validator: (value) =>
                  int.tryParse(value ?? '') == null || int.parse(value!) < 1
                  ? 'Enter at least 1 piece'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _product == null || _worker == null
            ? null
            : () {
                if (!_formKey.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  _ProductionDraft(
                    product: _product!,
                    worker: _worker!,
                    pieces: int.parse(_pieces.text),
                  ),
                );
              },
        child: const Text('Assign task'),
      ),
    ],
  );
}

class _PendingDraft {
  const _PendingDraft({required this.customer, required this.pieces});
  final Account customer;
  final int pieces;
}

class _PendingRequestDialog extends StatefulWidget {
  const _PendingRequestDialog({
    required this.product,
    required this.customers,
    required this.currentAccount,
  });
  final Product product;
  final List<Account> customers;
  final Account currentAccount;

  @override
  State<_PendingRequestDialog> createState() => _PendingRequestDialogState();
}

class _PendingRequestDialogState extends State<_PendingRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pieces = TextEditingController(text: '1');
  late Account _selected = widget.currentAccount.role == UserRole.customer
      ? widget.currentAccount
      : widget.customers.first;

  @override
  void dispose() {
    _pieces.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Request unavailable pieces'),
    content: SizedBox(
      width: 390,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.product.name} · ${widget.product.id}',
              style: const TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 12,
              ),
            ),
            if (widget.currentAccount.role != UserRole.customer) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Account>(
                initialValue: _selected,
                decoration: const InputDecoration(
                  labelText: 'Customer account',
                ),
                items: widget.customers
                    .map(
                      (customer) => DropdownMenuItem(
                        value: customer,
                        child: Text('${customer.name} · ${customer.id}'),
                      ),
                    )
                    .toList(),
                onChanged: (customer) {
                  if (customer != null) setState(() => _selected = customer);
                },
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _pieces,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pieces requested'),
              validator: (value) =>
                  int.tryParse(value ?? '') == null || int.parse(value!) < 1
                  ? 'Enter at least 1 piece'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'This request stays pending and is not added to the bill until stock is available.',
              style: TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _PendingDraft(customer: _selected, pieces: int.parse(_pieces.text)),
          );
        },
        child: const Text('Save pending request'),
      ),
    ],
  );
}

class BillsPage extends StatelessWidget {
  const BillsPage({
    super.key,
    required this.bills,
    required this.onDownload,
    this.canEditPrices = false,
    this.onEditLinePrice,
    this.onEditLineQuantity,
    this.onAddSale,
  });
  final List<Bill> bills;
  final ValueChanged<Bill> onDownload;
  final bool canEditPrices;
  final void Function(Bill bill, int lineIndex)? onEditLinePrice;
  final void Function(Bill bill, int lineIndex)? onEditLineQuantity;
  final VoidCallback? onAddSale;
  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'CHECKOUT',
    title: 'Bills & receipts',
    description: 'A clear record of product ID, quality, pieces, unit price, and balance.',
    action: onAddSale == null
        ? null
        : FilledButton.icon(
            onPressed: onAddSale,
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add sale'),
          ),
    child: bills.isEmpty
        ? const _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No bills yet',
            text: 'Create a sale from the shop to see its bill here.',
          )
        : Column(
            children: bills
                .map(
                  (bill) => _BillCard(
                    bill: bill,
                    onDownload: onDownload,
                    onEditLinePrice: canEditPrices ? onEditLinePrice : null,
                    onEditLineQuantity: canEditPrices
                        ? onEditLineQuantity
                        : null,
                  ),
                )
                .toList(),
          ),
  );
}

class CustomerDashboardPage extends StatelessWidget {
  const CustomerDashboardPage({
    super.key,
    required this.customerName,
    required this.orders,
    required this.bills,
    required this.pendingRequests,
    required this.onBrowse,
    required this.onOpenOrders,
    required this.onOpenBills,
    required this.onOpenPending,
  });
  final String customerName;
  final List<CustomerOrder> orders;
  final List<Bill> bills;
  final List<PendingRequest> pendingRequests;
  final VoidCallback onBrowse;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenBills;
  final VoidCallback onOpenPending;

  @override
  Widget build(BuildContext context) {
    final balance = bills.fold<double>(
      0,
      (total, bill) => total + bill.balance,
    );
    final openPending = pendingRequests
        .where((request) => request.status != PendingStatus.fulfilled)
        .length;
    return _PageFrame(
      eyebrow: 'YOUR ACCOUNT',
      title: 'Welcome, ${customerName.split(' ').first}',
      description: 'Track your jewellery orders, saved items, bills, and payments from one place.',
      action: FilledButton.icon(
        onPressed: onBrowse,
        icon: const Icon(Icons.storefront_outlined, size: 18),
        label: const Text('Browse collection'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MiniMetric(label: 'ORDERS', value: '${orders.length}'),
              _MiniMetric(label: 'PENDING ITEMS', value: '$openPending'),
              _MiniMetric(
                label: 'BALANCE DUE',
                value: _money(balance),
                emphasis: balance > 0,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent orders',
                        style: TextStyle(fontSize: 19),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenOrders,
                      child: const Text('View all'),
                    ),
                  ],
                ),
                if (orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Your orders will appear here after checkout.'),
                  )
                else
                  ...orders.take(4).map((order) {
                    final pieces = order.lines.fold<int>(
                      0,
                      (total, line) => total + line.pieces,
                    );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFF1EBDD),
                        child: Icon(Icons.local_mall_outlined, color: _gold),
                      ),
                      title: Text(order.id),
                      subtitle: Text(
                        '${_date(order.createdAt)} · $pieces pieces',
                      ),
                      trailing: _Badge(text: order.status.label),
                      onTap: onOpenOrders,
                    );
                  }),
                const Divider(color: _line),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onOpenPending,
                      icon: const Icon(Icons.hourglass_empty, size: 17),
                      label: Text('Pending items ($openPending)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenBills,
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: Text('Bills (${bills.length})'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.onDownload,
    this.onRecordPayment,
    this.onEditLinePrice,
    this.onEditLineQuantity,
  });
  final Bill bill;
  final ValueChanged<Bill> onDownload;
  final VoidCallback? onRecordPayment;
  final void Function(Bill bill, int lineIndex)? onEditLinePrice;
  final void Function(Bill bill, int lineIndex)? onEditLineQuantity;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 15),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.id, style: const TextStyle(fontSize: 19)),
                  const SizedBox(height: 5),
                  if (bill.createdByName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Sale created by ${bill.createdByName}',
                        style: const TextStyle(
                          color: _muted,
                          fontFamily: 'Arial',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  Text(
                    '${bill.customer}  ·  ${bill.customerId}  ·  ${_date(bill.createdAt)}',
                    style: const TextStyle(
                      color: _muted,
                      fontFamily: 'Arial',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money(bill.total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _Badge(
                  text: bill.paymentMode.name.toUpperCase(),
                  muted: bill.balance > 0,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _BillTableHeader(),
        const Divider(color: _line, height: 18),
        ...List<Widget>.generate(bill.lines.length, (lineIndex) {
          final line = bill.lines[lineIndex];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.name, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(
                        '${line.productId} · ${line.quality}',
                        style: const TextStyle(
                          color: _muted,
                          fontFamily: 'Arial',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${line.pieces}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 12,
                        ),
                      ),
                      if (onEditLineQuantity != null)
                        IconButton(
                          tooltip: 'Change bill quantity',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          onPressed: () => onEditLineQuantity!(bill, lineIndex),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(line.price),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 12,
                        ),
                      ),
                      if (onEditLinePrice != null)
                        IconButton(
                          tooltip: 'Change bill price',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          onPressed: () => onEditLinePrice!(bill, lineIndex),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    _money(line.total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(color: _line),
        _SummaryRow(label: 'Total', value: _money(bill.total)),
        const SizedBox(height: 6),
        _SummaryRow(label: 'Paid', value: _money(bill.paid)),
        const SizedBox(height: 6),
        _SummaryRow(
          label: 'Balance due',
          value: _money(bill.balance),
          strong: true,
        ),
        if (bill.payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('PAYMENTS', style: _tableHeader),
          ),
          const SizedBox(height: 4),
          ...bill.payments.map(
            (payment) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_date(payment.date)} · ${payment.note}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    _money(payment.amount),
                    style: const TextStyle(fontFamily: 'Arial', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onRecordPayment != null && bill.balance > 0) ...[
              OutlinedButton.icon(
                onPressed: onRecordPayment,
                icon: const Icon(Icons.add_card_outlined, size: 17),
                label: const Text('Record payment'),
              ),
              const SizedBox(width: 8),
            ],
            OutlinedButton.icon(
              onPressed: () => onDownload(bill),
              icon: const Icon(Icons.download_outlined, size: 17),
              label: const Text('Download receipt'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BillTableHeader extends StatelessWidget {
  const _BillTableHeader();
  @override
  Widget build(BuildContext context) => Row(
    children: const [
      Expanded(flex: 3, child: Text('PRODUCT', style: _tableHeader)),
      Expanded(
        child: Text('PIECES', textAlign: TextAlign.center, style: _tableHeader),
      ),
      Expanded(
        child: Text(
          'PRICE / PIECE',
          textAlign: TextAlign.right,
          style: _tableHeader,
        ),
      ),
      Expanded(
        child: Text('TOTAL', textAlign: TextAlign.right, style: _tableHeader),
      ),
    ],
  );
}

class _EditBillLinePriceDialog extends StatefulWidget {
  const _EditBillLinePriceDialog({required this.line});
  final BillLine line;

  @override
  State<_EditBillLinePriceDialog> createState() =>
      _EditBillLinePriceDialogState();
}

class _EditBillLinePriceDialogState extends State<_EditBillLinePriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price = TextEditingController(
    text: widget.line.price.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Change bill price'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.line.name} · ${widget.line.pieces} pieces',
            style: const TextStyle(
              color: _muted,
              fontFamily: 'Arial',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price per piece'),
            validator: (value) {
              final price = double.tryParse(value ?? '');
              if (price == null || !price.isFinite || price < 0) {
                return 'Enter a valid price';
              }
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, double.parse(_price.text));
          }
        },
        child: const Text('Save price'),
      ),
    ],
  );
}

class _EditBillLineQuantityDialog extends StatefulWidget {
  const _EditBillLineQuantityDialog({required this.line});
  final BillLine line;

  @override
  State<_EditBillLineQuantityDialog> createState() =>
      _EditBillLineQuantityDialogState();
}

class _EditBillLineQuantityDialogState
    extends State<_EditBillLineQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pieces = TextEditingController(
    text: widget.line.pieces.toString(),
  );

  @override
  void dispose() {
    _pieces.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Edit bill quantity'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.line.name} · originally ordered ${widget.line.orderedPieces}',
            style: const TextStyle(
              color: _muted,
              fontFamily: 'Arial',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pieces,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Pieces on this bill'),
            validator: (value) {
              final pieces = int.tryParse(value ?? '');
              if (pieces == null || pieces < 0) {
                return 'Enter zero or a positive whole number';
              }
              if (pieces > widget.line.orderedPieces) {
                return 'Cannot exceed the original quantity of ${widget.line.orderedPieces}';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Any quantity removed from the bill is saved to this customer’s pending items.',
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: 11,
              color: _muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, int.parse(_pieces.text));
          }
        },
        child: const Text('Save quantity'),
      ),
    ],
  );
}

const _tableHeader = TextStyle(
  color: _muted,
  fontFamily: 'Arial',
  fontSize: 9,
  letterSpacing: .8,
  fontWeight: FontWeight.w600,
);

class OrdersPage extends StatelessWidget {
  const OrdersPage({
    super.key,
    required this.orders,
    required this.pendingRequests,
    required this.products,
    required this.bills,
    required this.account,
    required this.onOrderStatusChanged,
    required this.onMarkSeen,
    required this.onAddPending,
    required this.onRefreshPending,
    required this.onDownload,
  });

  final List<CustomerOrder> orders;
  final List<PendingRequest> pendingRequests;
  final List<Product> products;
  final List<Bill> bills;
  final Account account;
  final void Function(CustomerOrder, OrderStatus) onOrderStatusChanged;
  final ValueChanged<CustomerOrder> onMarkSeen;
  final ValueChanged<PendingRequest> onAddPending;
  final ValueChanged<Product> onRefreshPending;
  final ValueChanged<Bill> onDownload;

  bool get _isCustomer => account.role == UserRole.customer;

  @override
  Widget build(BuildContext context) {
    final visibleOrders = _isCustomer
        ? orders.where((order) => order.customerId == account.id).toList()
        : orders;
    final visibleRequests = _isCustomer
        ? pendingRequests
              .where((request) => request.customerId == account.id)
              .toList()
        : pendingRequests;
    final pendingByCustomer = <String, List<PendingRequest>>{};
    if (!_isCustomer) {
      for (final request in visibleRequests.where(
        (request) => request.status != PendingStatus.fulfilled,
      )) {
        pendingByCustomer
            .putIfAbsent(request.customerId, () => [])
            .add(request);
      }
    }
    final unseen = _isCustomer
        ? 0
        : visibleOrders.where((order) => !order.seenByStaff).length;
    return _PageFrame(
      eyebrow: _isCustomer ? 'YOUR ACCOUNT' : 'SALES DESK',
      title: _isCustomer ? 'Your orders' : 'Orders inbox',
      description: _isCustomer
          ? 'Track placed orders and see items waiting for stock.'
          : 'New orders and pending stock requests, grouped by customer.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isCustomer && unseen > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF1EBDD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, color: _gold),
                  const SizedBox(width: 10),
                  Text(
                    '$unseen new customer ${unseen == 1 ? 'order' : 'orders'}',
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text(
            _isCustomer ? 'Order history' : 'Incoming orders',
            style: const TextStyle(fontSize: 21),
          ),
          const SizedBox(height: 12),
          if (visibleOrders.isEmpty)
            const _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No orders yet',
              text: 'Orders placed by customers will appear here.',
            )
          else
            ...visibleOrders.map((order) {
              final bill = _findBill(order.billId);
              return _OrderCard(
                order: order,
                isCustomer: _isCustomer,
                bill: bill,
                onStatusChanged: (status) =>
                    onOrderStatusChanged(order, status),
                onMarkSeen: () => onMarkSeen(order),
                onDownload: bill == null ? null : () => onDownload(bill),
              );
            }),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isCustomer ? 'Pending items' : 'Pending stock by customer',
                  style: const TextStyle(fontSize: 21),
                ),
              ),
              if (visibleRequests.isNotEmpty)
                _Badge(
                  text:
                      '${visibleRequests.where((request) => request.status != PendingStatus.fulfilled).length} OPEN',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleRequests.isEmpty)
            const _EmptyState(
              icon: Icons.hourglass_empty,
              title: 'No pending items',
              text:
                  'Unavailable items requested by customers will appear here.',
            )
          else if (_isCustomer)
            ...visibleRequests.map(
              (request) => _PendingRequestCard(
                request: request,
                product: _findProduct(request.productId),
                canAdd: request.status == PendingStatus.ready,
                onAdd: () => onAddPending(request),
                onRefresh: () => _refreshFor(request),
              ),
            )
          else if (pendingByCustomer.isEmpty)
            const _EmptyState(
              icon: Icons.hourglass_empty,
              title: 'No pending items',
              text: 'There are no open stock requests from customers.',
            )
          else
            ...pendingByCustomer.entries.map((entry) {
              final requests = entry.value
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final customer = requests.first;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _line),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF1EBDD),
                      foregroundColor: _gold,
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      customer.customerName,
                      style: const TextStyle(fontSize: 15),
                    ),
                    subtitle: Text(
                      '${customer.customerId} · ${requests.length} pending ${requests.length == 1 ? 'item' : 'items'}',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        color: _muted,
                        fontSize: 11,
                      ),
                    ),
                    children: requests
                        .map(
                          (request) => Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                            child: _PendingRequestCard(
                              request: request,
                              product: _findProduct(request.productId),
                              canAdd: false,
                              onAdd: () {},
                              onRefresh: () => _refreshFor(request),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Product? _findProduct(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Bill? _findBill(String id) {
    for (final bill in bills) {
      if (bill.id == id) return bill;
    }
    return null;
  }

  void _refreshFor(PendingRequest request) {
    final product = _findProduct(request.productId);
    if (product != null) onRefreshPending(product);
  }
}

class PendingItemsPage extends StatelessWidget {
  const PendingItemsPage({
    super.key,
    required this.requests,
    required this.products,
    required this.onAdd,
    required this.onRefresh,
  });

  final List<PendingRequest> requests;
  final List<Product> products;
  final ValueChanged<PendingRequest> onAdd;
  final ValueChanged<Product> onRefresh;

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'YOUR ACCOUNT',
    title: 'Pending items',
    description: 'Items you asked us to reserve when stock becomes available.',
    child: requests.isEmpty
        ? const _EmptyState(
            icon: Icons.hourglass_empty,
            title: 'No pending items',
            text: 'Use “Request when available” on an out-of-stock item to save it here.',
          )
        : Column(
            children: requests.map((request) {
              Product? product;
              for (final candidate in products) {
                if (candidate.id == request.productId) {
                  product = candidate;
                  break;
                }
              }
              return _PendingRequestCard(
                request: request,
                product: product,
                canAdd: request.status == PendingStatus.ready,
                onAdd: () => onAdd(request),
                onRefresh: product == null ? () {} : () => onRefresh(product!),
              );
            }).toList(),
          ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isCustomer,
    required this.bill,
    required this.onStatusChanged,
    required this.onMarkSeen,
    required this.onDownload,
  });
  final CustomerOrder order;
  final bool isCustomer;
  final Bill? bill;
  final ValueChanged<OrderStatus> onStatusChanged;
  final VoidCallback onMarkSeen;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(order.id, style: const TextStyle(fontSize: 17)),
                      if (!isCustomer && !order.seenByStaff) ...[
                        const SizedBox(width: 8),
                        const _Badge(text: 'NEW'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.customerName} · ${order.customerId} · ${_date(order.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: _muted,
                      fontSize: 10,
                    ),
                  ),
                  if (order.placedByName.isNotEmpty &&
                      order.placedByName != order.customerName)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Placed by ${order.placedByName}',
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!isCustomer && !order.seenByStaff)
              IconButton(
                tooltip: 'Mark as seen',
                onPressed: onMarkSeen,
                icon: const Icon(Icons.mark_email_read_outlined, color: _gold),
              ),
          ],
        ),
        const SizedBox(height: 11),
        ...order.lines.map(
          (line) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.name, style: const TextStyle(fontSize: 13)),
                      Text(
                        '${line.productId} · ${line.quality}',
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${line.pieces} pcs × ${_money(line.price)}',
                  style: const TextStyle(fontFamily: 'Arial', fontSize: 11),
                ),
                const SizedBox(width: 10),
                Text(
                  _money(line.total),
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(color: _line),
        Row(
          children: [
            Expanded(
              child: Text(
                'Order total  ${_money(order.lines.fold(0, (sum, line) => sum + line.total))}',
                style: const TextStyle(
                  fontFamily: 'Arial',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if (bill != null)
              _Badge(
                text:
                    bill!.paymentMode == PaymentMode.credit && bill!.balance > 0
                    ? 'CREDIT DUE'
                    : 'PAID',
                muted: bill!.balance > 0,
              ),
          ],
        ),
        if (isCustomer || onDownload != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download receipt'),
            ),
          ),
        ],
        if (!isCustomer) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Status',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: _muted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<OrderStatus>(
                value: order.status,
                underline: const SizedBox.shrink(),
                items: OrderStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(
                          status.label,
                          style: const TextStyle(
                            fontFamily: 'Arial',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (status) {
                  if (status != null) onStatusChanged(status);
                },
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({
    required this.request,
    required this.product,
    required this.canAdd,
    required this.onAdd,
    required this.onRefresh,
  });
  final PendingRequest request;
  final Product? product;
  final bool canAdd;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFBFAF7),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        const Icon(Icons.hourglass_top_rounded, size: 20, color: _gold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(request.productName, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 3),
              Text(
                '${request.productId} · ${request.quality} · ${request.pieces} pieces · ${_money(request.pricePerPiece)} each',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Arial',
                  color: _muted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${request.status.label} · Requested ${_date(request.createdAt)}',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: request.status == PendingStatus.ready
                      ? const Color(0xFF4F7D52)
                      : _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (canAdd && request.status == PendingStatus.ready)
          TextButton(onPressed: onAdd, child: const Text('Add to bag'))
        else if (product != null && request.status == PendingStatus.pending)
          IconButton(
            tooltip: 'Check stock',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: _muted),
          ),
      ],
    ),
  );
}

class TeamPage extends StatelessWidget {
  const TeamPage({
    super.key,
    required this.accounts,
    required this.applications,
    required this.currentAccount,
    required this.onCreate,
    required this.onApprove,
    required this.onReject,
    required this.onChanged,
  });
  final List<Account> accounts;
  final List<AccountApplication> applications;
  final Account currentAccount;
  final ValueChanged<Account> onCreate;
  final ValueChanged<AccountApplication> onApprove;
  final ValueChanged<AccountApplication> onReject;
  final ValueChanged<Account> onChanged;

  @override
  Widget build(BuildContext context) {
    final admins = accounts.where((account) => account.isAdmin).length;
    return _PageFrame(
      eyebrow: 'ACCESS CONTROL',
      title: 'People & permissions',
      description: currentAccount.isOwner
          ? 'Add employees to the store team and review account access.'
          : 'Create customer and staff accounts. The store can have up to two admins.',
      action: FilledButton.icon(
        onPressed: () async {
          final account = await showDialog<Account>(
            context: context,
            builder: (_) => _AccountForm(
              currentAccount: currentAccount,
              adminLimitReached: admins >= 2,
              existingLogins: accounts
                  .map((a) => a.login.toLowerCase())
                  .toSet(),
            ),
          );
          if (account != null) onCreate(account);
        },
        icon: const Icon(Icons.person_add_alt_1, size: 18),
        label: const Text('Create account'),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1EBDD),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: _gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$admins of 2 admin accounts used. Grant only the permissions each person needs.',
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: _ink,
                      height: 1.4,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (currentAccount.isAdmin) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pending access requests (${applications.length})',
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(height: 10),
            if (applications.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _line),
                ),
                child: const Text(
                  'No customer requests are waiting for approval.',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ...applications.map(
                (application) => _AccountApplicationCard(
                  application: application,
                  onApprove: () => onApprove(application),
                  onReject: () => onReject(application),
                ),
              ),
            const SizedBox(height: 12),
            const Divider(color: _line),
            const SizedBox(height: 12),
          ],
          ...accounts.map(
            (account) => _AccountCard(
              account: account,
              onEdit: currentAccount.isAdmin
                  ? () => _editPermissions(context, account)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPermissions(BuildContext context, Account account) async {
    final permissions = await showDialog<_PermissionSelection>(
      context: context,
      builder: (_) => _EditPermissionsDialog(account: account),
    );
    if (permissions == null) return;
    account.canShop = permissions.canShop;
    account.canManageStock = account.role == UserRole.customer
        ? false
        : permissions.canManageStock;
    account.canCreateBills = account.role == UserRole.customer
        ? false
        : permissions.canCreateBills;
    onChanged(account);
  }
}

class CustomersPage extends StatelessWidget {
  const CustomersPage({
    super.key,
    required this.customers,
    required this.bills,
    required this.orders,
    required this.pendingRequests,
    required this.onPayment,
    required this.onDownload,
  });
  final List<Account> customers;
  final List<Bill> bills;
  final List<CustomerOrder> orders;
  final List<PendingRequest> pendingRequests;
  final void Function(Bill, double) onPayment;
  final ValueChanged<Bill> onDownload;

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'CUSTOMER ACCOUNTS',
    title: 'Customers',
    description: 'Open a customer account to review orders, bills, payments, and balance due.',
    child: customers.isEmpty
        ? const _EmptyState(
            icon: Icons.people_outline,
            title: 'No customer accounts',
            text: 'An administrator can create customer accounts in People & permissions.',
          )
        : Column(
            children: customers.map((customer) {
              final customerBills = bills
                  .where((bill) => bill.customerId == customer.id)
                  .toList();
              final balance = customerBills.fold<double>(
                0,
                (sum, bill) => sum + bill.balance,
              );
              final orderCount = orders
                  .where((order) => order.customerId == customer.id)
                  .length;
              final pendingCount = pendingRequests
                  .where(
                    (request) =>
                        request.customerId == customer.id &&
                        request.status != PendingStatus.fulfilled,
                  )
                  .length;
              return InkWell(
                onTap: () => _openCustomer(context, customer),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFF1EBDD),
                        foregroundColor: _gold,
                        child: Text(
                          customer.name.isEmpty
                              ? '?'
                              : customer.name[0].toUpperCase(),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${customer.id} · ${customer.login}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Arial',
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$orderCount orders · ${customerBills.length} bills · $pendingCount pending items',
                              style: const TextStyle(
                                fontFamily: 'Arial',
                                color: _muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('BALANCE DUE', style: _tableHeader),
                          const SizedBox(height: 4),
                          Text(
                            _money(balance),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: balance > 0
                                  ? const Color(0xFF9B4F3F)
                                  : _ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 7),
                      const Icon(Icons.chevron_right, color: _muted),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
  );

  Future<void> _openCustomer(BuildContext context, Account customer) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CustomerDetailDialog(
        customer: customer,
        bills: bills.where((bill) => bill.customerId == customer.id).toList(),
        orders: orders
            .where((order) => order.customerId == customer.id)
            .toList(),
        pendingRequests: pendingRequests
            .where((request) => request.customerId == customer.id)
            .toList(),
        onPayment: onPayment,
        onDownload: onDownload,
      ),
    );
  }
}

class _CustomerDetailDialog extends StatefulWidget {
  const _CustomerDetailDialog({
    required this.customer,
    required this.bills,
    required this.orders,
    required this.pendingRequests,
    required this.onPayment,
    required this.onDownload,
  });
  final Account customer;
  final List<Bill> bills;
  final List<CustomerOrder> orders;
  final List<PendingRequest> pendingRequests;
  final void Function(Bill, double) onPayment;
  final ValueChanged<Bill> onDownload;

  @override
  State<_CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends State<_CustomerDetailDialog> {
  double get _balance =>
      widget.bills.fold(0, (sum, bill) => sum + bill.balance);
  double get _paid => widget.bills.fold(0, (sum, bill) => sum + bill.paid);

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: _paper,
    insetPadding: const EdgeInsets.all(18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
      child: Padding(
        padding: const EdgeInsets.all(23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customer.name,
                        style: const TextStyle(fontSize: 25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.customer.id} · ${widget.customer.login.isEmpty ? (widget.customer.phone.isEmpty ? 'Walk-in customer' : widget.customer.phone) : widget.customer.login}',
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniMetric(label: 'TOTAL PAID', value: _money(_paid)),
                _MiniMetric(
                  label: 'BALANCE DUE',
                  value: _money(_balance),
                  emphasis: _balance > 0,
                ),
                _MiniMetric(label: 'ORDERS', value: '${widget.orders.length}'),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  if (widget.orders.isNotEmpty) ...[
                    const Text('Orders', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 9),
                    ...widget.orders.map(
                      (order) => _OrderCard(
                        order: order,
                        isCustomer: true,
                        bill: _findBill(order.billId),
                        onStatusChanged: (_) {},
                        onMarkSeen: () {},
                        onDownload: _findBill(order.billId) == null
                            ? null
                            : () => widget.onDownload(_findBill(order.billId)!),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.pendingRequests.isNotEmpty) ...[
                    const Text('Pending items', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 9),
                    ...widget.pendingRequests.map(
                      (request) => _PendingRequestCard(
                        request: request,
                        product: null,
                        canAdd: false,
                        onAdd: () {},
                        onRefresh: () {},
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Bills and payments',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 9),
                  if (widget.bills.isEmpty)
                    const _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No bills yet',
                      text: 'Bills created for this customer will appear here.',
                    )
                  else
                    ...widget.bills.map(
                      (bill) => _BillCard(
                        bill: bill,
                        onDownload: widget.onDownload,
                        onRecordPayment: bill.balance <= 0
                            ? null
                            : () => _recordPayment(bill),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Bill? _findBill(String id) {
    for (final bill in widget.bills) {
      if (bill.id == id) return bill;
    }
    return null;
  }

  Future<void> _recordPayment(Bill bill) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _RecordPaymentDialog(bill: bill),
    );
    if (amount == null) return;
    widget.onPayment(bill, amount);
    if (mounted) setState(() {});
  }
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.bill});
  final Bill bill;
  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text: widget.bill.balance.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Record customer payment'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.bill.customer} · ${widget.bill.id}',
            style: const TextStyle(
              fontFamily: 'Arial',
              color: _muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Amount due: ${_money(widget.bill.balance)}',
            style: const TextStyle(
              fontFamily: 'Arial',
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Payment amount'),
            validator: (value) {
              final amount = double.tryParse(value ?? '');
              if (amount == null || amount <= 0) {
                return 'Enter a valid amount';
              }
              if (amount - widget.bill.balance > .001) {
                return 'Payment cannot exceed the balance due';
              }
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, double.parse(_amount.text));
          }
        },
        child: const Text('Record payment'),
      ),
    ],
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Container(
    width: 175,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _tableHeader),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: emphasis ? const Color(0xFF9B4F3F) : _ink,
          ),
        ),
      ],
    ),
  );
}

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({
    super.key,
    required this.orders,
    required this.bills,
    required this.pendingRequests,
  });
  final List<CustomerOrder> orders;
  final List<Bill> bills;
  final List<PendingRequest> pendingRequests;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayBills = bills
        .where((bill) => _sameDay(bill.createdAt, today))
        .toList();
    final salesToday = todayBills.fold<double>(
      0,
      (sum, bill) => sum + bill.total,
    );
    final cashToday = bills
        .expand((bill) => bill.payments)
        .where((payment) => _sameDay(payment.date, today))
        .fold<double>(0, (sum, payment) => sum + payment.amount);
    final creditToday = todayBills
        .where((bill) => bill.paymentMode == PaymentMode.credit)
        .fold<double>(0, (sum, bill) => sum + bill.total);
    final outstanding = bills.fold<double>(
      0,
      (sum, bill) => sum + bill.balance,
    );
    final openRequests = pendingRequests
        .where((request) => request.status != PendingStatus.fulfilled)
        .length;
    final days = List.generate(
      7,
      (index) => DateTime(today.year, today.month, today.day - 6 + index),
    );
    final sales = days
        .map(
          (day) => bills
              .where((bill) => _sameDay(bill.createdAt, day))
              .fold<double>(0, (sum, bill) => sum + bill.total),
        )
        .toList();
    final maximum = sales.fold<double>(
      0,
      (value, sale) => sale > value ? sale : value,
    );
    return _PageFrame(
      eyebrow: 'BUSINESS OVERVIEW',
      title: 'Daily sales & statistics',
      description: 'Business day totals, cash received, credit issued, and customer balances.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 700 ? 4 : 2;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatCard(
                    width: itemWidth,
                    label: 'SALES TODAY',
                    value: _money(salesToday),
                    icon: Icons.trending_up,
                  ),
                  _StatCard(
                    width: itemWidth,
                    label: 'CASH RECEIVED',
                    value: _money(cashToday),
                    icon: Icons.payments_outlined,
                  ),
                  _StatCard(
                    width: itemWidth,
                    label: 'CREDIT ISSUED',
                    value: _money(creditToday),
                    icon: Icons.schedule_outlined,
                  ),
                  _StatCard(
                    width: itemWidth,
                    label: 'BALANCE DUE',
                    value: _money(outstanding),
                    icon: Icons.account_balance_wallet_outlined,
                    danger: outstanding > 0,
                  ),
                  _StatCard(
                    width: itemWidth,
                    label: 'ORDERS TODAY',
                    value:
                        '${orders.where((order) => _sameDay(order.createdAt, today)).length}',
                    icon: Icons.receipt_long_outlined,
                  ),
                  _StatCard(
                    width: itemWidth,
                    label: 'PENDING ITEMS',
                    value: '$openRequests',
                    icon: Icons.hourglass_top_rounded,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sales by business day',
                  style: TextStyle(fontSize: 19),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Last 7 days · totals from orders placed',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (index) {
                      final height = maximum == 0
                          ? 3.0
                          : (sales[index] / maximum * 105)
                                .clamp(3.0, 105.0)
                                .toDouble();
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                sales[index] == 0
                                    ? '–'
                                    : _compactMoney(sales[index]),
                                style: const TextStyle(
                                  fontFamily: 'Arial',
                                  color: _muted,
                                  fontSize: 8,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: index == 6
                                      ? _gold
                                      : const Color(0xFFDCCBA8),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${days[index].day}/${days[index].month}',
                                style: const TextStyle(
                                  fontFamily: 'Arial',
                                  color: _muted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: danger ? const Color(0xFF9B4F3F) : _gold),
        const SizedBox(height: 12),
        Text(label, style: _tableHeader),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: danger ? const Color(0xFF9B4F3F) : _ink,
          ),
        ),
      ],
    ),
  );
}

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({
    super.key,
    required this.business,
    required this.onChanged,
  });
  final BusinessProfile business;
  final VoidCallback onChanged;
  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.business.name);
  late final _address = TextEditingController(text: widget.business.address);
  late final _phone = TextEditingController(text: widget.business.phone);

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'STORE SETTINGS',
    title: 'Business profile',
    description: 'These details appear on customer receipts.',
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter the business name'
                  : null,
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Business phone (optional)',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save business profile'),
            ),
          ],
        ),
      ),
    ),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.business.name = _name.text.trim();
    widget.business.address = _address.text.trim();
    widget.business.phone = _phone.text.trim();
    widget.onChanged();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Business profile saved.')));
  }
}

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.account,
    required this.existingLogins,
    required this.onChanged,
    this.firebaseEnabled = false,
  });
  final Account account;
  final Set<String> existingLogins;
  final VoidCallback onChanged;
  final bool firebaseEnabled;
  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account.name);
  late final _login = TextEditingController(text: widget.account.login);
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    eyebrow: 'MY ACCOUNT',
    title: 'Account settings',
    description: widget.firebaseEnabled
        ? 'Update your profile. Firebase manages your sign-in email and password.'
        : 'Update your name and sign-in details.',
    child: Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account ID  ·  ${widget.account.id}  ·  ${widget.account.role.label}',
              style: const TextStyle(
                fontFamily: 'Arial',
                color: _muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _login,
              readOnly: widget.firebaseEnabled,
              decoration: const InputDecoration(
                labelText: 'Email or phone number',
              ),
              validator: (value) {
                final login = value?.trim().toLowerCase() ?? '';
                if (login.isEmpty) {
                  return 'Enter an email or phone number';
                }
                if (login != widget.account.login.toLowerCase() &&
                    widget.existingLogins.contains(login)) {
                  return 'This sign-in is already in use';
                }
                return null;
              },
            ),
            if (!widget.firebaseEnabled) ...[
              const SizedBox(height: 13),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password (leave blank to keep current)',
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save account'),
            ),
          ],
        ),
      ),
    ),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.account.name = _name.text.trim();
    if (!widget.firebaseEnabled) {
      widget.account.login = _login.text.trim();
      if (_password.text.isNotEmpty) widget.account.password = _password.text;
    }
    widget.onChanged();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Account updated.')));
  }
}

class _AccountApplicationCard extends StatelessWidget {
  const _AccountApplicationCard({
    required this.application,
    required this.onApprove,
    required this.onReject,
  });

  final AccountApplication application;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    margin: const EdgeInsets.only(bottom: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFF1EBDD),
              foregroundColor: _gold,
              child: Text(
                application.name.isEmpty
                    ? '?'
                    : application.name[0].toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(application.name, style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(
                    application.email,
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Requested ${_date(application.createdAt)}',
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      color: _muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const _Badge(text: 'PENDING'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 7,
          children: [
            FilledButton.icon(
              onPressed: onApprove,
              icon: const Icon(Icons.check, size: 17),
              label: const Text('Approve customer'),
            ),
            OutlinedButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.close, size: 17),
              label: const Text('Decline'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.onEdit});
  final Account account;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final permissions = <String>[
      if (account.canShop) 'Shop',
      if (account.canManageStock) 'Manage stock',
      if (account.canCreateBills) 'Create bills',
      if (account.isAdmin) 'Create accounts',
    ];
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFF1EBDD),
            foregroundColor: _gold,
            child: Text(
              account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  '${account.id}  ·  ${account.login}',
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  permissions.isEmpty
                      ? 'No permissions assigned'
                      : permissions.join('  ·  '),
                  style: const TextStyle(
                    fontFamily: 'Arial',
                    color: _muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          _RolePill(role: account.role),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit permissions',
            icon: const Icon(Icons.tune_outlined, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _PermissionSelection {
  const _PermissionSelection({
    required this.canShop,
    required this.canManageStock,
    required this.canCreateBills,
  });

  final bool canShop;
  final bool canManageStock;
  final bool canCreateBills;
}

class _EditPermissionsDialog extends StatefulWidget {
  const _EditPermissionsDialog({required this.account});
  final Account account;

  @override
  State<_EditPermissionsDialog> createState() => _EditPermissionsDialogState();
}

class _EditPermissionsDialogState extends State<_EditPermissionsDialog> {
  late bool _canShop = widget.account.canShop;
  late bool _canManageStock = widget.account.canManageStock;
  late bool _canCreateBills = widget.account.canCreateBills;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: Text('Permissions for ${widget.account.name}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PermissionSwitch(
          title: 'Browse and shop',
          value: _canShop,
          onChanged: (value) => setState(() => _canShop = value),
        ),
        if (widget.account.role != UserRole.customer) ...[
          _PermissionSwitch(
            title: 'Manage inventory and stock',
            value: _canManageStock,
            onChanged: (value) => setState(() => _canManageStock = value),
          ),
          _PermissionSwitch(
            title: 'Create bills',
            value: _canCreateBills,
            onChanged: (value) => setState(() => _canCreateBills = value),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _PermissionSelection(
            canShop: _canShop,
            canManageStock: _canManageStock,
            canCreateBills: _canCreateBills,
          ),
        ),
        child: const Text('Save permissions'),
      ),
    ],
  );
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({
    required this.currentAccount,
    required this.adminLimitReached,
    required this.existingLogins,
  });
  final Account currentAccount;
  final bool adminLimitReached;
  final Set<String> existingLogins;
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  late UserRole _role = widget.currentAccount.isOwner
      ? UserRole.employee
      : UserRole.customer;
  bool _canShop = true;
  late bool _canManageStock = widget.currentAccount.isOwner;
  late bool _canCreateBills = widget.currentAccount.isOwner;

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  void _selectRole(UserRole? role) {
    if (role == null) return;
    setState(() {
      _role = role;
      switch (role) {
        case UserRole.admin:
        case UserRole.owner:
        case UserRole.employee:
          _canShop = true;
          _canManageStock = true;
          _canCreateBills = true;
          break;
        case UserRole.customer:
          _canShop = true;
          _canManageStock = false;
          _canCreateBills = false;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 490),
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Create an account', style: TextStyle(fontSize: 25)),
                const SizedBox(height: 7),
                const Text(
                  'Set sign-in details and choose what this person can do.',
                  style: TextStyle(
                    color: _muted,
                    fontFamily: 'Arial',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 19),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _login,
                  decoration: const InputDecoration(
                    labelText: 'Email or phone number',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter an email or phone number';
                    }
                    if (widget.existingLogins.contains(
                      v.trim().toLowerCase(),
                    )) {
                      return 'This sign-in is already in use';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                  ),
                  obscureText: true,
                  validator: (v) => v == null || v.length < 6
                      ? 'Use at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items:
                      (widget.currentAccount.isOwner
                              ? const [UserRole.employee]
                              : UserRole.values.where(
                                  (role) =>
                                      role != UserRole.admin ||
                                      !widget.adminLimitReached,
                                ))
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role.label),
                            ),
                          )
                          .toList(),
                  onChanged: _selectRole,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Permissions',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Arial',
                    fontSize: 13,
                  ),
                ),
                _PermissionSwitch(
                  title: 'Browse and shop',
                  value: _canShop,
                  onChanged: (value) => setState(() => _canShop = value),
                ),
                _PermissionSwitch(
                  title: 'Manage inventory and stock',
                  value: _canManageStock,
                  onChanged: (value) => setState(() => _canManageStock = value),
                ),
                _PermissionSwitch(
                  title: 'Create bills',
                  value: _canCreateBills,
                  onChanged: (value) => setState(() => _canCreateBills = value),
                ),
                if (_role == UserRole.admin)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.adminLimitReached
                          ? 'The two-admin limit has been reached.'
                          : 'Admins can also create accounts.',
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 11,
                        color: _muted,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final prefix = switch (_role) {
      UserRole.admin => 'ADM',
      UserRole.owner => 'OWN',
      UserRole.employee => 'EMP',
      UserRole.customer => 'CUS',
    };
    Navigator.pop(
      context,
      Account(
        id: '$prefix-${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim(),
        login: _login.text.trim(),
        password: _password.text,
        role: _role,
        canShop: _canShop,
        canManageStock: _canManageStock,
        canCreateBills: _canCreateBills,
      ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontFamily: 'Arial', fontSize: 12),
    ),
    value: value,
    activeThumbColor: _gold,
    onChanged: onChanged,
  );
}

class _AccessPage extends StatelessWidget {
  const _AccessPage();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(30),
      child: _EmptyState(
        icon: Icons.lock_outline,
        title: 'No access assigned',
        text: 'Ask an administrator to grant you access to the shop, inventory, or billing.',
      ),
    ),
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
    this.action,
  });
  final String eyebrow;
  final String title;
  final String description;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(28, 30, 28, 35),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Overline(eyebrow),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 31)),
                      const SizedBox(height: 7),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          color: _muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 14, top: 2),
                    child: action!,
                  ),
              ],
            ),
            const SizedBox(height: 23),
            child,
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 55),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
    ),
    child: Column(
      children: [
        Icon(icon, color: _gold, size: 38),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 7),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Arial',
            color: _muted,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.account,
    this.onMenu,
    required this.cartCount,
    required this.orderCount,
    required this.onSearch,
    required this.onCart,
    required this.onOrders,
    required this.onLogout,
  });
  final Account account;
  final VoidCallback? onMenu;
  final int cartCount;
  final int orderCount;
  final ValueChanged<String> onSearch;
  final VoidCallback? onCart;
  final VoidCallback? onOrders;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tiny = width < 430;
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(
        horizontal: width < 380
            ? 12
            : width < 430
            ? 16
            : 25,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (onMenu != null)
            IconButton(
              tooltip: 'Open navigation menu',
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              onPressed: onMenu,
              icon: const Icon(Icons.menu),
            ),
          if (width >= 620 && width < 1000) const _BrandLockup(compact: true),
          const Spacer(),
          SizedBox(
            width: width < 380
                ? 94
                : width < 430
                ? 112
                : width < 500
                ? 105
                : width < 620
                ? 140
                : width < 760
                ? 150
                : 210,
            height: 41,
            child: TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                hintText: 'Find a piece...',
                prefixIcon: Icon(Icons.search, size: 19),
                contentPadding: EdgeInsets.symmetric(vertical: 7),
                isDense: true,
              ),
            ),
          ),
          if (onCart != null)
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: _CartIcon(
                count: cartCount,
                onPressed: onCart!,
                compact: tiny,
              ),
            ),
          if (onOrders != null)
            IconButton(
              tooltip: 'Orders and notifications',
              constraints: tiny
                  ? const BoxConstraints.tightFor(width: 36, height: 36)
                  : null,
              padding: tiny ? const EdgeInsets.all(6) : null,
              onPressed: onOrders,
              icon: _OrdersIcon(count: orderCount),
            ),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (_) => onLogout(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFFF1EBDD),
                  foregroundColor: _gold,
                  child: Text(
                    account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (width >= 620)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        account.name,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        account.role.label,
                        style: const TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 10,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(width: 3),
                const Icon(Icons.keyboard_arrow_down, size: 17, color: _muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartIcon extends StatelessWidget {
  const _CartIcon({
    required this.count,
    required this.onPressed,
    required this.compact,
  });
  final int count;
  final VoidCallback onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: 'Open bag',
    constraints: compact
        ? const BoxConstraints.tightFor(width: 36, height: 36)
        : null,
    padding: compact ? const EdgeInsets.all(6) : null,
    icon: Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.shopping_bag_outlined),
        if (count > 0)
          Positioned(
            right: -8,
            top: -7,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Arial',
                  fontSize: 8,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _OrdersIcon extends StatelessWidget {
  const _OrdersIcon({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Icon(Icons.notifications_none_outlined),
      if (count > 0)
        Positioned(
          right: -8,
          top: -7,
          child: Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Arial',
                fontSize: 8,
              ),
            ),
          ),
        ),
    ],
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.width,
    required this.compact,
    required this.account,
    required this.page,
    required this.pages,
    required this.cartCount,
    required this.orderCount,
    required this.onSelect,
    required this.onLogout,
  });
  final double width;
  final bool compact;
  final Account account;
  final _Page page;
  final List<_Page> pages;
  final int cartCount;
  final int orderCount;
  final ValueChanged<_Page> onSelect;
  final VoidCallback onLogout;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    color: const Color(0xFF262521),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(15, 16, 12, 12)
              : const EdgeInsets.fromLTRB(24, 27, 20, 34),
          child: const _BrandLockup(light: true),
        ),
        if (!compact) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: _Overline('WORKSPACE', light: true),
          ),
          const SizedBox(height: 13),
        ],
        Expanded(
          child: Column(
            children: pages
                .map(
                  (item) => compact
                      ? Expanded(
                          child: _NavItem(
                            page: item,
                            selected: page == item,
                            compact: true,
                            count: item == _Page.cart
                                ? cartCount
                                : item == _Page.orders
                                ? orderCount
                                : 0,
                            onTap: () => onSelect(item),
                          ),
                        )
                      : _NavItem(
                          page: item,
                          selected: page == item,
                          compact: false,
                          count: item == _Page.cart
                              ? cartCount
                              : item == _Page.orders
                              ? orderCount
                              : 0,
                          onTap: () => onSelect(item),
                        ),
                )
                .toList(),
          ),
        ),
        Padding(
          padding: compact ? const EdgeInsets.all(9) : const EdgeInsets.all(15),
          child: Container(
            padding: EdgeInsets.all(compact ? 9 : 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_outlined,
                  color: Color(0xFFD9BF8B),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Arial',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        account.role.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .56),
                          fontFamily: 'Arial',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: onLogout,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.logout,
                    color: Colors.white.withValues(alpha: .75),
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.page,
    required this.selected,
    required this.compact,
    required this.count,
    required this.onTap,
  });
  final _Page page;
  final bool selected;
  final bool compact;
  final int count;
  final VoidCallback onTap;
  String get _label => switch (page) {
    _Page.customerDashboard => 'My dashboard',
    _Page.shop => 'Shop collection',
    _Page.inventory => 'Inventory',
    _Page.production => 'Production tasks',
    _Page.cart => 'Your bag',
    _Page.orders => 'Orders inbox',
    _Page.pending => 'Pending items',
    _Page.bills => 'Bills & receipts',
    _Page.customers => 'Customers',
    _Page.statistics => 'Sales & statistics',
    _Page.team => 'People & access',
    _Page.settings => 'Business settings',
    _Page.account => 'My account',
    _Page.access => 'Access needed',
  };
  IconData get _icon => switch (page) {
    _Page.customerDashboard => Icons.dashboard_outlined,
    _Page.shop => Icons.auto_awesome_outlined,
    _Page.inventory => Icons.inventory_2_outlined,
    _Page.production => Icons.precision_manufacturing_outlined,
    _Page.cart => Icons.shopping_bag_outlined,
    _Page.orders => Icons.notifications_active_outlined,
    _Page.pending => Icons.hourglass_empty,
    _Page.bills => Icons.receipt_long_outlined,
    _Page.customers => Icons.people_outline,
    _Page.statistics => Icons.bar_chart_outlined,
    _Page.team => Icons.groups_2_outlined,
    _Page.settings => Icons.settings_outlined,
    _Page.account => Icons.manage_accounts_outlined,
    _Page.access => Icons.lock_outline,
  };
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 12,
      vertical: compact ? 0 : 3,
    ),
    child: Material(
      color: selected ? const Color(0xFF413B30) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 13,
            vertical: compact ? 2 : 13,
          ),
          child: Row(
            children: [
              Icon(
                _icon,
                color: selected ? const Color(0xFFD9BF8B) : Colors.white70,
                size: 19,
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontFamily: 'Arial',
                    fontSize: compact ? 12 : 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (count > 0) _NavCount(count: count),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavCount extends StatelessWidget {
  const _NavCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _gold,
      borderRadius: BorderRadius.circular(50),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'Arial',
        fontSize: 9,
      ),
    ),
  );
}

pw.Document _createReceiptPdf(BusinessProfile business, Bill bill) {
  const gold = PdfColor(.69, .54, .28);
  const rule = PdfColor(.89, .86, .81);
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(38),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 42,
              height: 42,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: gold, width: 1.5),
              ),
              child: pw.Center(
                child: pw.Text(
                  'PJ',
                  style: pw.TextStyle(
                    color: gold,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    business.name,
                    style: pw.TextStyle(
                      fontSize: 21,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'JEWELLERY ORDER RECEIPT',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.4,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              bill.id,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Divider(color: gold, thickness: 1.2),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'CUSTOMER',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    bill.customer,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Customer ID: ${bill.customerId}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'DATE',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _date(bill.createdAt),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'Payment: ${bill.paymentMode.name.toUpperCase()}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (business.address.trim().isNotEmpty ||
            business.phone.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            [
              business.address,
              business.phone,
            ].where((value) => value.trim().isNotEmpty).join('   |   '),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 21),
        pw.Table(
          border: pw.TableBorder.all(color: rule, width: .6),
          columnWidths: const {
            0: pw.FlexColumnWidth(3.5),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColor(.96, .95, .92),
              ),
              children: ['PRODUCT / ID', 'PIECES', 'PRICE / PIECE', 'TOTAL']
                  .map(
                    (text) => pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        text,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            ...bill.lines.map(
              (line) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          line.name,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '${line.productId}  |  ${line.quality}',
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      '${line.pieces}',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      _pdfMoney(line.price),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      _pdfMoney(line.total),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 225,
            child: pw.Column(
              children: [
                _pdfSummaryRow('Total', bill.total),
                pw.SizedBox(height: 6),
                _pdfSummaryRow('Paid', bill.paid),
                pw.SizedBox(height: 6),
                pw.Divider(color: rule),
                _pdfSummaryRow('BALANCE DUE', bill.balance, strong: true),
              ],
            ),
          ),
        ),
        if (bill.payments.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            'PAYMENT HISTORY',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 7),
          ...bill.payments.map(
            (payment) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '${_date(payment.date)}  |  ${payment.note}',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ),
                  pw.Text(
                    _pdfMoney(payment.amount),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ),
        ],
        pw.SizedBox(height: 34),
        pw.Divider(color: rule),
        pw.Center(
          child: pw.Text(
            'Thank you for choosing ${business.name}.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ],
    ),
  );
  return document;
}

pw.Widget _pdfSummaryRow(String label, double value, {bool strong = false}) =>
    pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: strong ? 10 : 9,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          _pdfMoney(value),
          style: pw.TextStyle(
            fontSize: strong ? 10 : 9,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );

String _pdfMoney(double value) => 'INR ${value.toStringAsFixed(2)}';

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final UserRole role;
  @override
  Widget build(BuildContext context) {
    final admin = role == UserRole.admin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: admin ? const Color(0xFFF3ECDE) : const Color(0xFFF4F3F0),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          color: admin ? _gold : _muted,
          fontFamily: 'Arial',
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.light = false, this.compact = false});
  final bool light;
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 33 : 39,
        height: compact ? 33 : 39,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: light ? const Color(0xFFDBC595) : _gold),
        ),
        child: Icon(
          Icons.auto_awesome,
          size: compact ? 17 : 20,
          color: light ? const Color(0xFFDBC595) : _gold,
        ),
      ),
      const SizedBox(width: 11),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROGRESSIVE',
            style: TextStyle(
              color: light ? Colors.white : _ink,
              fontFamily: 'Georgia',
              fontSize: compact ? 12 : 14,
              letterSpacing: 1.7,
            ),
          ),
          if (!compact)
            Text(
              'J E W E L L E R Y',
              style: TextStyle(
                color: light ? Colors.white70 : _muted,
                fontFamily: 'Arial',
                fontSize: 8,
                letterSpacing: 1.55,
              ),
            ),
        ],
      ),
    ],
  );
}

class _Overline extends StatelessWidget {
  const _Overline(this.text, {this.light = false});
  final String text;
  final bool light;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Arial',
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
      color: light ? Colors.white.withValues(alpha: .68) : _gold,
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Arial',
            fontSize: strong ? 14 : 12,
            color: strong ? _ink : _muted,
            fontWeight: strong ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'Arial',
          fontSize: strong ? 16 : 13,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ],
  );
}

String _money(double value) =>
    '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_month(date.month)} ${date.year}';

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _compactMoney(double value) {
  if (value >= 10000000) return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
  if (value >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
  if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(0)}k';
  return '₹${value.toStringAsFixed(0)}';
}

String _month(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];
