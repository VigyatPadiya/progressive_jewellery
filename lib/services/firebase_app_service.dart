import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FirebaseAppService {
  FirebaseAppService._();

  static const storeId = 'progressive-jewellery';
  static const _region = 'asia-south1';

  static bool get isConfigured => Firebase.apps.isNotEmpty;

  static FirebaseAuth get auth => FirebaseAuth.instance;

  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: _region);

  static CollectionReference<Map<String, dynamic>> _collection(String name) =>
      firestore.collection('stores/$storeId/$name');

  static DocumentReference<Map<String, dynamic>> memberDocument(String uid) =>
      firestore.doc('stores/$storeId/members/$uid');

  static DocumentReference<Map<String, dynamic>> applicationDocument(
      String uid,
      ) =>
      firestore.doc('stores/$storeId/applications/$uid');

  // ============================================================
  // CLOUD FUNCTION HELPER
  //
  // Windows desktop:
  //   Uses HTTPS callable protocol directly because the Flutter
  //   Cloud Functions platform channel is not available there.
  //
  // Android / iOS / Web / macOS:
  //   Uses the normal Firebase Cloud Functions SDK.
  // ============================================================

  static Future<dynamic> _callFunction(
      String functionName,
      Map<String, dynamic> data,
      ) async {
    // ------------------------------------------------------------
    // WINDOWS DESKTOP
    // ------------------------------------------------------------
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final user = auth.currentUser;

      if (user == null) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'You must be signed in to use this function.',
        );
      }

      final token = await user.getIdToken();

      if (token == null || token.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'Could not obtain Firebase authentication token.',
        );
      }

      final projectId = Firebase.app().options.projectId;

      if (projectId.isEmpty) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Firebase project ID is not configured.',
        );
      }

      final uri = Uri.parse(
        'https://$_region-$projectId.cloudfunctions.net/$functionName',
      );

      try {
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'data': data,
          }),
        );

        dynamic decoded;

        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = null;
        }

        // --------------------------------------------------------
        // SUCCESS
        // --------------------------------------------------------
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          if (decoded is Map<String, dynamic> &&
              decoded.containsKey('data')) {
            return decoded['data'];
          }

          return decoded;
        }

        // --------------------------------------------------------
        // FIREBASE CALLABLE ERROR
        // --------------------------------------------------------
        if (decoded is Map<String, dynamic> &&
            decoded['error'] is Map<String, dynamic>) {
          final error = Map<String, dynamic>.from(
            decoded['error'] as Map,
          );

          final rawCode =
              error['status']?.toString() ?? 'internal';

          final message =
              error['message']?.toString() ??
                  'Firebase Cloud Function failed.';

          final details = error['details'];

          throw FirebaseFunctionsException(
            code: _normaliseFunctionErrorCode(rawCode),
            message: message,
            details: details,
          );
        }

        throw FirebaseFunctionsException(
          code: 'internal',
          message:
          'Cloud Function failed with HTTP ${response.statusCode}. '
              '${response.body}',
        );
      } catch (e) {
        if (e is FirebaseFunctionsException) {
          rethrow;
        }

        throw FirebaseFunctionsException(
          code: 'unavailable',
          message:
          'Could not connect to Firebase Cloud Function '
              '$functionName: $e',
        );
      }
    }

    // ------------------------------------------------------------
    // NORMAL FIREBASE SDK
    // Android / iOS / Web / macOS
    // ------------------------------------------------------------

    final callable = functions.httpsCallable(functionName);

    final result = await callable.call(data);

    return result.data;
  }

  static String _normaliseFunctionErrorCode(String code) {
    switch (code.toUpperCase()) {
      case 'OK':
        return 'ok';

      case 'CANCELLED':
        return 'cancelled';

      case 'UNKNOWN':
        return 'unknown';

      case 'INVALID_ARGUMENT':
        return 'invalid-argument';

      case 'DEADLINE_EXCEEDED':
        return 'deadline-exceeded';

      case 'NOT_FOUND':
        return 'not-found';

      case 'ALREADY_EXISTS':
        return 'already-exists';

      case 'PERMISSION_DENIED':
        return 'permission-denied';

      case 'UNAUTHENTICATED':
        return 'unauthenticated';

      case 'RESOURCE_EXHAUSTED':
        return 'resource-exhausted';

      case 'FAILED_PRECONDITION':
        return 'failed-precondition';

      case 'ABORTED':
        return 'aborted';

      case 'OUT_OF_RANGE':
        return 'out-of-range';

      case 'UNIMPLEMENTED':
        return 'unimplemented';

      case 'INTERNAL':
        return 'internal';

      case 'UNAVAILABLE':
        return 'unavailable';

      case 'DATA_LOSS':
        return 'data-loss';

      default:
        return code.toLowerCase();
    }
  }

  // ============================================================
  // ACCOUNT APPLICATION
  // ============================================================

  static Future<void> submitAccountApplication({
    required String name,
  }) async {
    try {
      await _callFunction(
        'submitStoreAccountApplication',
        {
          'storeId': storeId,
          'name': name.trim(),
        },
      );
    } catch (e) {
      // Fallback for Windows desktop if Cloud Functions fail.
      final uid = auth.currentUser?.uid;
      final email = auth.currentUser?.email;

      if (uid != null && email != null) {
        await applicationDocument(uid).set({
          'name': name.trim(),
          'email': email,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        rethrow;
      }
    }
  }

  // ============================================================
  // APPROVE ACCOUNT
  // ============================================================

  static Future<void> approveAccountApplication(String uid) async {
    try {
      await _callFunction(
        'approveStoreAccountApplication',
        {
          'storeId': storeId,
          'uid': uid,
        },
      );
    } catch (e) {
      final doc = await applicationDocument(uid).get();
      final data = doc.data();

      if (data != null) {
        await applicationDocument(uid).update({
          'status': 'approved',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await memberDocument(uid).set({
          'uid': uid,
          'id': 'CUS-${DateTime.now().millisecondsSinceEpoch}',
          'name': data['name'] ?? 'Customer',
          'email': data['email'] ?? '',
          'role': 'customer',
          'canShop': true,
          'canManageStock': false,
          'canCreateBills': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        rethrow;
      }
    }
  }

  // ============================================================
  // REJECT ACCOUNT
  // ============================================================

  static Future<void> rejectAccountApplication(String uid) async {
    try {
      await _callFunction(
        'rejectStoreAccountApplication',
        {
          'storeId': storeId,
          'uid': uid,
        },
      );
    } catch (e) {
      await applicationDocument(uid).update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================================
  // LOAD MEMBER
  // ============================================================

  static Future<Map<String, dynamic>?> loadMember(String uid) async {
    final snapshot = await memberDocument(uid).get();
    return snapshot.data();
  }

  // ============================================================
  // CREATE ACCOUNT
  // ============================================================

  static Future<void> createAccount({
    required String accountId,
    required String name,
    required String email,
    required String password,
    required String role,
    required bool canShop,
    required bool canManageStock,
    required bool canCreateBills,
  }) async {
    await _callFunction(
      'createStoreAccount',
      {
        'storeId': storeId,
        'accountId': accountId,
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        'canShop': canShop,
        'canManageStock': canManageStock,
        'canCreateBills': canCreateBills,
      },
    );
  }

  // ============================================================
  // PLACE ORDER
  // ============================================================

  static Future<Map<String, dynamic>> placeOrder({
    String? customerUid,
    String? manualCustomerDocumentId,
    required String paymentMode,
    required List<Map<String, Object>> lines,
  }) async {
    final result = await _callFunction(
      'placeOrder',
      {
        'storeId': storeId,
        if (customerUid != null)
          'customerUid': customerUid,
        if (manualCustomerDocumentId != null)
          'manualCustomerDocumentId': manualCustomerDocumentId,
        'paymentMode': paymentMode,
        'lines': lines,
      },
    );

    if (result is Map<String, dynamic>) {
      return result;
    }

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Invalid response received from placeOrder.',
    );
  }

  // ============================================================
  // MANUAL CUSTOMER
  // ============================================================

  static Future<void> saveManualCustomer({
    required String id,
    required String name,
    required String phone,
  }) =>
      _collection('customers').doc(id).set({
        'id': id,
        'name': name.trim(),
        'phone': phone.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  // ============================================================
  // PRODUCTION TASK
  // ============================================================

  static Future<void> createProductionTask({
    required String id,
    required String productId,
    required String productName,
    required int currentStock,
    required int piecesToMake,
    required String workerUid,
    required String workerName,
    required String assignedByName,
  }) =>
      _collection('productionTasks').doc(id).set({
        'id': id,
        'productId': productId,
        'productName': productName,
        'currentStock': currentStock,
        'piecesToMake': piecesToMake,
        'workerUid': workerUid,
        'workerName': workerName,
        'assignedByName': assignedByName,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'assigned',
      });

  // ============================================================
  // UPDATE PRODUCTION TASK STATUS
  // ============================================================

  static Future<void> updateProductionTaskStatus({
    required String taskDocumentId,
    required String status,
  }) async {
    await _callFunction(
      'updateProductionTaskStatus',
      {
        'storeId': storeId,
        'taskDocumentId': taskDocumentId,
        'status': status,
      },
    );
  }

  // ============================================================
  // UPDATE ORDER STATUS
  // ============================================================

  static Future<void> updateOrderStatus({
    required String orderDocumentId,
    required String status,
  }) async {
    await _callFunction(
      'updateOrderStatus',
      {
        'storeId': storeId,
        'orderDocumentId': orderDocumentId,
        'status': status,
      },
    );
  }

  // ============================================================
  // UPDATE BILL LINE PRICE
  // ============================================================

  static Future<void> updateBillLinePrice({
    required String billDocumentId,
    required int lineIndex,
    required double price,
  }) async {
    try {
      await _callFunction(
        'updateBillLinePrice',
        {
          'storeId': storeId,
          'billDocumentId': billDocumentId,
          'lineIndex': lineIndex,
          'price': price,
        },
      );
    } catch (e) {
      // Fallback for Windows desktop
      final docRef = _collection('bills').doc(billDocumentId);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final lines = List<Map<String, dynamic>>.from(
          (data['lines'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)),
        );
        if (lineIndex >= 0 && lineIndex < lines.length) {
          lines[lineIndex]['price'] = price;
          await docRef.update({
            'lines': lines,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }
  }

  // ============================================================
  // UPDATE BILL LINE QUANTITY
  // ============================================================

  static Future<void> updateBillLineQuantity({
    required String billDocumentId,
    required int lineIndex,
    required int pieces,
  }) async {
    try {
      await _callFunction(
        'updateBillLineQuantity',
        {
          'storeId': storeId,
          'billDocumentId': billDocumentId,
          'lineIndex': lineIndex,
          'pieces': pieces,
        },
      );
    } catch (e) {
      // Fallback for Windows desktop
      final docRef = _collection('bills').doc(billDocumentId);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data()!;
        final lines = List<Map<String, dynamic>>.from(
          (data['lines'] as List? ?? []).map((x) => Map<String, dynamic>.from(x)),
        );
        if (lineIndex >= 0 && lineIndex < lines.length) {
          lines[lineIndex]['pieces'] = pieces;
          await docRef.update({
            'lines': lines,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }
  }

  static Future<void> deleteBill(String documentId) async {
    await _collection('bills').doc(documentId).delete();
  }

  // ============================================================
  // MARK ORDER SEEN
  // ============================================================

  static Future<void> markOrderSeen(String documentId) =>
      _collection('orders').doc(documentId).update({
        'seenByStaff': true,
      });

  static Future<void> deleteOrder(String documentId) async {
    await _collection('orders').doc(documentId).delete();
  }

  // ============================================================
  // SAVE PENDING REQUEST
  // ============================================================

  static Future<void> savePendingRequest({
    required String id,
    required String customerUid,
    required String customerId,
    required String customerName,
    required String productId,
    required String productName,
    required String quality,
    required double pricePerPiece,
    required int pieces,
  }) =>
      _collection('pendingRequests').doc(id).set({
        'id': id,
        'customerUid': customerUid,
        'customerId': customerId,
        'customerName': customerName,
        'productId': productId,
        'productName': productName,
        'quality': quality,
        'pricePerPiece': pricePerPiece,
        'pieces': pieces,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

  // ============================================================
  // UPDATE PENDING STATUS
  // ============================================================

  static Future<void> updatePendingStatus(
      String documentId,
      String status,
      ) async {
    await _callFunction(
      'updatePendingStatus',
      {
        'storeId': storeId,
        'requestDocumentId': documentId,
        'status': status,
      },
    );
  }

  // ============================================================
  // SAVE CART
  // ============================================================

  static Future<void> saveCart(
      String uid,
      Map<String, int> items,
      ) =>
      firestore.doc('stores/$storeId/carts/$uid').set({
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ============================================================
  // SAVE PRODUCT
  // ============================================================

  static Future<String> saveProduct({
    required String id,
    required String name,
    required String quality,
    required double price,
    required int stock,
    required String imageUrl,
    required Uint8List? imageBytes,
    required String description,
    required String category,
    required DateTime createdAt,
  }) async {
    var savedImageUrl = imageUrl.trim();

    if (imageBytes != null && imageBytes.isNotEmpty) {
      final user = auth.currentUser;

      print('========== FIREBASE AUTH CHECK ==========');
      print('User: $user');
      print('UID: ${user?.uid}');
      print('Email: ${user?.email}');
      print('=========================================');

      if (user == null) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message:
          'You must be signed in before uploading a product image.',
        );
      }

      try {
        final safeId = id.trim().replaceAll(
          RegExp(r'[^a-zA-Z0-9_-]'),
          '_',
        );

        final imageRef = FirebaseStorage.instance
            .ref()
            .child('stores')
            .child(storeId)
            .child('productImages')
            .child('$safeId.jpg');

        final isPng = imageBytes.length >= 4 &&
            imageBytes[0] == 0x89 &&
            imageBytes[1] == 0x50 &&
            imageBytes[2] == 0x4E &&
            imageBytes[3] == 0x47;

        final metadata = SettableMetadata(
          contentType: isPng ? 'image/png' : 'image/jpeg',
          cacheControl: 'public,max-age=3600',
        );

        await imageRef.putData(
          imageBytes,
          metadata,
        );

        savedImageUrl = await imageRef.getDownloadURL();
      } on FirebaseException catch (e) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: e.code,
          message:
          'Product image upload failed: ${e.message ?? e.code}',
        );
      }
    }

    await _collection('products').doc(id).set({
      'id': id,
      'name': name,
      'quality': quality,
      'price': price,
      'stock': stock,
      'imageUrl': savedImageUrl,
      'description': description,
      'category': category,
      'createdAt': createdAt,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return savedImageUrl;
  }

  // ============================================================
  // DELETE PRODUCT
  // ============================================================

  static Future<void> deleteProduct(String id) async {
    await _collection('products').doc(id).delete();
  }

  // ============================================================
  // SAVE CATEGORY
  // ============================================================

  static Future<void> saveCategory(String category) =>
      _collection('categories')
          .doc(_categoryKey(category))
          .set({
        'name': category,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static String _categoryKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  // ============================================================
  // SAVE BUSINESS
  // ============================================================

  static Future<void> saveBusiness({
    required String name,
    required String address,
    required String phone,
  }) =>
      firestore.doc('stores/$storeId/business/profile').set({
        'name': name,
        'address': address,
        'phone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ============================================================
  // ADD BILL PAYMENT
  // ============================================================

  static Future<void> addBillPayment(
      String documentId,
      Map<String, Object?> payment,
      ) =>
      _collection('bills').doc(documentId).update({
        'payments': FieldValue.arrayUnion([payment]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ============================================================
  // UPDATE MEMBER PROFILE
  // ============================================================

  static Future<void> updateMemberProfile({
    required String uid,
    String? name,
    String? phone,
    bool? canShop,
    bool? canManageStock,
    bool? canCreateBills,
  }) async {
    try {
      await _callFunction(
        'updateStoreMember',
        {
          'storeId': storeId,
          'uid': uid,
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (canShop != null) 'canShop': canShop,
          if (canManageStock != null)
            'canManageStock': canManageStock,
          if (canCreateBills != null)
            'canCreateBills': canCreateBills,
        },
      );
    } catch (e) {
      await memberDocument(uid).update({
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (canShop != null) 'canShop': canShop,
        if (canManageStock != null)
          'canManageStock': canManageStock,
        if (canCreateBills != null)
          'canCreateBills': canCreateBills,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================================
  // DELETE MEMBER
  // ============================================================

  static Future<void> deleteMember(String uid) async {
    try {
      await _callFunction(
        'deleteStoreMember',
        {
          'storeId': storeId,
          'uid': uid,
        },
      );
    } catch (e) {
      await memberDocument(uid).delete();
    }
  }
}