import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  static Future<Map<String, dynamic>?> loadMember(String uid) async {
    final snapshot = await memberDocument(uid).get();
    return snapshot.data();
  }

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
    await functions.httpsCallable('createStoreAccount').call({
      'storeId': storeId,
      'accountId': accountId,
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'canShop': canShop,
      'canManageStock': canManageStock,
      'canCreateBills': canCreateBills,
    });
  }

  static Future<Map<String, dynamic>> placeOrder({
    String? customerUid,
    String? manualCustomerDocumentId,
    required String paymentMode,
    required List<Map<String, Object>> lines,
  }) async {
    final result = await functions.httpsCallable('placeOrder').call({
      'storeId': storeId,
      if (customerUid != null) 'customerUid': customerUid,
      if (manualCustomerDocumentId != null)
        'manualCustomerDocumentId': manualCustomerDocumentId,
      'paymentMode': paymentMode,
      'lines': lines,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> saveManualCustomer({
    required String id,
    required String name,
    required String phone,
  }) => _collection('customers').doc(id).set({
    'id': id,
    'name': name.trim(),
    'phone': phone.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  static Future<void> createProductionTask({
    required String id,
    required String productId,
    required String productName,
    required int currentStock,
    required int piecesToMake,
    required String workerUid,
    required String workerName,
    required String assignedByName,
  }) => _collection('productionTasks').doc(id).set({
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

  static Future<void> updateProductionTaskStatus({
    required String taskDocumentId,
    required String status,
  }) async {
    await functions.httpsCallable('updateProductionTaskStatus').call({
      'storeId': storeId,
      'taskDocumentId': taskDocumentId,
      'status': status,
    });
  }

  static Future<void> updateOrderStatus({
    required String orderDocumentId,
    required String status,
  }) async {
    await functions.httpsCallable('updateOrderStatus').call({
      'storeId': storeId,
      'orderDocumentId': orderDocumentId,
      'status': status,
    });
  }

  static Future<void> updateBillLinePrice({
    required String billDocumentId,
    required int lineIndex,
    required double price,
  }) async {
    await functions.httpsCallable('updateBillLinePrice').call({
      'storeId': storeId,
      'billDocumentId': billDocumentId,
      'lineIndex': lineIndex,
      'price': price,
    });
  }

  static Future<void> updateBillLineQuantity({
    required String billDocumentId,
    required int lineIndex,
    required int pieces,
  }) async {
    await functions.httpsCallable('updateBillLineQuantity').call({
      'storeId': storeId,
      'billDocumentId': billDocumentId,
      'lineIndex': lineIndex,
      'pieces': pieces,
    });
  }

  static Future<void> markOrderSeen(String documentId) =>
      _collection('orders').doc(documentId).update({'seenByStaff': true});

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
  }) => _collection('pendingRequests').doc(id).set({
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

  static Future<void> updatePendingStatus(
    String documentId,
    String status,
  ) async {
    await functions.httpsCallable('updatePendingStatus').call({
      'storeId': storeId,
      'requestDocumentId': documentId,
      'status': status,
    });
  }

  static Future<void> saveCart(String uid, Map<String, int> items) => firestore
      .doc('stores/$storeId/carts/$uid')
      .set({'items': items, 'updatedAt': FieldValue.serverTimestamp()});

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
    var savedImageUrl = imageUrl;
    if (imageBytes != null) {
      final imageRef = FirebaseStorage.instance.ref(
        'stores/$storeId/productImages/${Uri.encodeComponent(id)}',
      );
      final isPng =
          imageBytes.length >= 4 &&
          imageBytes[0] == 0x89 &&
          imageBytes[1] == 0x50 &&
          imageBytes[2] == 0x4e &&
          imageBytes[3] == 0x47;
      await imageRef.putData(
        imageBytes,
        SettableMetadata(contentType: isPng ? 'image/png' : 'image/jpeg'),
      );
      savedImageUrl = await imageRef.getDownloadURL();
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

  static Future<void> saveCategory(String category) =>
      _collection('categories')
          .doc(_categoryKey(category))
          .set({'name': category, 'createdAt': FieldValue.serverTimestamp()});

  static String _categoryKey(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static Future<void> saveBusiness({
    required String name,
    required String address,
    required String phone,
  }) => firestore.doc('stores/$storeId/business/profile').set({
    'name': name,
    'address': address,
    'phone': phone,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> addBillPayment(
    String documentId,
    Map<String, Object?> payment,
  ) => _collection('bills').doc(documentId).update({
    'payments': FieldValue.arrayUnion([payment]),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  static Future<void> updateMemberProfile({
    required String uid,
    String? name,
    bool? canShop,
    bool? canManageStock,
    bool? canCreateBills,
  }) async {
    await functions.httpsCallable('updateStoreMember').call({
      'storeId': storeId,
      'uid': uid,
      if (name != null) 'name': name,
      if (canShop != null) 'canShop': canShop,
      if (canManageStock != null) 'canManageStock': canManageStock,
      if (canCreateBills != null) 'canCreateBills': canCreateBills,
    });
  }
}
