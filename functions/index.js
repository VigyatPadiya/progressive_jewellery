const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore();
const region = "asia-south1";
const allowedRoles = new Set(["admin", "owner", "employee", "customer"]);
const orderStatuses = new Set(["received", "preparing", "ready", "completed"]);

function storeMemberRef(storeId, uid) {
  return db.doc(`stores/${storeId}/members/${uid}`);
}

async function requireCaller(request, storeId) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }

  const snapshot = await storeMemberRef(storeId, request.auth.uid).get();
  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "This account is not in this store.");
  }
  const member = snapshot.data();
  return {
    ...member,
    role: String(member.role ?? "customer").trim().toLowerCase(),
  };
}

exports.createStoreAccount = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  if (!storeId) {
    throw new HttpsError("invalid-argument", "A store ID is required.");
  }

  const caller = await requireCaller(request, storeId);
  const role = String(request.data?.role ?? "customer").trim().toLowerCase();
  const isOwnerAddingEmployee = caller.role === "owner" && role === "employee";
  if (caller.role !== "admin" && !isOwnerAddingEmployee) {
    throw new HttpsError("permission-denied", "Owners can add employees; only admins can create other account types.");
  }
  const name = String(request.data?.name ?? "").trim();
  const email = String(request.data?.email ?? "").trim().toLowerCase();
  const password = String(request.data?.password ?? "");
  const accountId = String(request.data?.accountId ?? "").trim();

  if (!name || !email || password.length < 6 || !accountId || !allowedRoles.has(role)) {
    throw new HttpsError("invalid-argument", "Complete all account fields with a valid email and password.");
  }

  const members = db.collection(`stores/${storeId}/members`);
  const duplicateAccount = await members.where("id", "==", accountId).limit(1).get();
  if (!duplicateAccount.empty) {
    throw new HttpsError("already-exists", "That account ID is already in use.");
  }

  if (role === "admin") {
    const admins = await members.where("role", "==", "admin").limit(2).get();
    if (admins.size >= 2) {
      throw new HttpsError("failed-precondition", "This store already has two admin accounts.");
    }
  }

  let userRecord;
  try {
    userRecord = await getAuth().createUser({
      email,
      password,
      displayName: name,
    });

    await storeMemberRef(storeId, userRecord.uid).set({
      uid: userRecord.uid,
      id: accountId,
      name,
      email,
      login: email,
      role,
      canShop: role === "customer" || request.data?.canShop === true,
      canManageStock: role !== "customer" && request.data?.canManageStock === true,
      canCreateBills: role !== "customer" && request.data?.canCreateBills === true,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (userRecord) await getAuth().deleteUser(userRecord.uid).catch(() => {});
    if (error instanceof HttpsError) throw error;
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account already uses that email.");
    }
    throw new HttpsError("internal", "The account could not be created.");
  }

  return { uid: userRecord.uid };
});

exports.submitStoreAccountApplication = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const name = String(request.data?.name ?? "").trim();
  const uid = request.auth?.uid;
  const email = String(request.auth?.token?.email ?? "").trim().toLowerCase();
  if (!uid) {
    throw new HttpsError("unauthenticated", "Create an account before requesting store access.");
  }
  if (storeId !== "progressive-jewellery"
      || !name || name.length > 120 || !email) {
    throw new HttpsError("invalid-argument", "Enter your name and create an email account first.");
  }

  const userRecord = await getAuth().getUser(uid);
  if (userRecord.disabled || userRecord.email?.toLowerCase() !== email) {
    throw new HttpsError("permission-denied", "This sign-in cannot request store access.");
  }

  const memberRef = storeMemberRef(storeId, uid);
  const applicationRef = db.doc(`stores/${storeId}/applications/${uid}`);
  await db.runTransaction(async (transaction) => {
    const [memberSnapshot, applicationSnapshot] = await Promise.all([
      transaction.get(memberRef),
      transaction.get(applicationRef),
    ]);
    if (memberSnapshot.exists) {
      throw new HttpsError("already-exists", "This account already has store access.");
    }
    if (applicationSnapshot.exists
        && applicationSnapshot.data().status === "pending") {
      return;
    }
    transaction.set(applicationRef, {
      uid,
      name,
      email,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { status: "pending" };
});

exports.approveStoreAccountApplication = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const targetUid = String(request.data?.uid ?? "").trim();
  if (!storeId || !targetUid) {
    throw new HttpsError("invalid-argument", "A store account request is required.");
  }
  const caller = await requireCaller(request, storeId);
  if (caller.role !== "admin") {
    throw new HttpsError("permission-denied", "Only an admin can approve account access.");
  }

  const applicationRef = db.doc(`stores/${storeId}/applications/${targetUid}`);
  const memberRef = storeMemberRef(storeId, targetUid);
  const applicationSnapshot = await applicationRef.get();
  if (!applicationSnapshot.exists
      || applicationSnapshot.data().status !== "pending") {
    throw new HttpsError("not-found", "This account request is no longer pending.");
  }
  const application = applicationSnapshot.data();
  let userRecord;
  try {
    userRecord = await getAuth().getUser(targetUid);
  } catch (_) {
    throw new HttpsError("failed-precondition", "The applicant's sign-in account no longer exists.");
  }
  if (userRecord.disabled
      || userRecord.email?.toLowerCase() !== String(application.email ?? "").toLowerCase()) {
    throw new HttpsError("failed-precondition", "The applicant's sign-in account could not be verified.");
  }

  await db.runTransaction(async (transaction) => {
    const [latestApplication, latestMember] = await Promise.all([
      transaction.get(applicationRef),
      transaction.get(memberRef),
    ]);
    if (!latestApplication.exists
        || latestApplication.data().status !== "pending") {
      throw new HttpsError("failed-precondition", "This account request is no longer pending.");
    }
    if (latestMember.exists) {
      throw new HttpsError("already-exists", "This account already has store access.");
    }
    const data = latestApplication.data();
    transaction.set(memberRef, {
      uid: targetUid,
      id: `CUS-${targetUid.toUpperCase()}`,
      name: String(data.name ?? "Customer"),
      email: String(data.email ?? userRecord.email ?? ""),
      login: String(data.email ?? userRecord.email ?? ""),
      role: "customer",
      canShop: true,
      canManageStock: false,
      canCreateBills: false,
      createdAt: FieldValue.serverTimestamp(),
      approvedBy: request.auth.uid,
      approvedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(applicationRef, {
      status: "approved",
      approvedBy: request.auth.uid,
      approvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await getAuth().updateUser(targetUid, { displayName: String(application.name ?? "") });
  return { uid: targetUid };
});

exports.rejectStoreAccountApplication = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const targetUid = String(request.data?.uid ?? "").trim();
  if (!storeId || !targetUid) {
    throw new HttpsError("invalid-argument", "A store account request is required.");
  }
  const caller = await requireCaller(request, storeId);
  if (caller.role !== "admin") {
    throw new HttpsError("permission-denied", "Only an admin can reject account access.");
  }

  const applicationRef = db.doc(`stores/${storeId}/applications/${targetUid}`);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(applicationRef);
    if (!snapshot.exists || snapshot.data().status !== "pending") {
      throw new HttpsError("not-found", "This account request is no longer pending.");
    }
    transaction.update(applicationRef, {
      status: "rejected",
      rejectedBy: request.auth.uid,
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});

exports.updateStoreMember = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const targetUid = String(request.data?.uid ?? "").trim();
  if (!storeId || !targetUid) {
    throw new HttpsError("invalid-argument", "A store and member are required.");
  }

  const caller = await requireCaller(request, storeId);
  const isSelf = request.auth.uid === targetUid;
  const targetRef = storeMemberRef(storeId, targetUid);
  const targetSnapshot = await targetRef.get();
  if (!targetSnapshot.exists) {
    throw new HttpsError("not-found", "That store member was not found.");
  }

  const updates = {};
  if (typeof request.data?.name === "string") {
    const name = request.data.name.trim();
    if (!name) {
      throw new HttpsError("invalid-argument", "A name is required.");
    }
    updates.name = name;
  }

  const hasPermissionChanges = ["canShop", "canManageStock", "canCreateBills"]
    .some((key) => Object.hasOwn(request.data ?? {}, key));
  if (hasPermissionChanges && caller.role !== "admin") {
    throw new HttpsError("permission-denied", "Only an admin can change permissions.");
  }
  if (hasPermissionChanges) {
    if (targetSnapshot.data().role === "customer"
        && (request.data?.canManageStock === true
          || request.data?.canCreateBills === true)) {
      throw new HttpsError("failed-precondition", "Customer accounts cannot manage stock or create bills.");
    }
    for (const key of ["canShop", "canManageStock", "canCreateBills"]) {
      if (Object.hasOwn(request.data ?? {}, key)) {
        if (typeof request.data[key] !== "boolean") {
          throw new HttpsError("invalid-argument", "Permissions must be true or false.");
        }
        updates[key] = request.data[key];
      }
    }
  }
  if (!isSelf && caller.role !== "admin") {
    throw new HttpsError("permission-denied", "Only an admin can update another member.");
  }
  if (!Object.keys(updates).length) {
    throw new HttpsError("invalid-argument", "There are no account changes to save.");
  }

  updates.updatedAt = FieldValue.serverTimestamp();
  await targetRef.update(updates);
  if (isSelf && updates.name) {
    await getAuth().updateUser(targetUid, { displayName: updates.name });
  }
  return { ok: true };
});

exports.updatePendingStatus = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const requestDocumentId = String(request.data?.requestDocumentId ?? "").trim();
  const status = String(request.data?.status ?? "");
  if (!storeId || !requestDocumentId || !new Set(["pending", "ready", "fulfilled"]).has(status)) {
    throw new HttpsError("invalid-argument", "The pending request update is invalid.");
  }

  const caller = await requireCaller(request, storeId);
  const requestRef = db.doc(`stores/${storeId}/pendingRequests/${requestDocumentId}`);
  const requestSnapshot = await requestRef.get();
  if (!requestSnapshot.exists) {
    throw new HttpsError("not-found", "The pending request was not found.");
  }
  const pending = requestSnapshot.data();
  const isCustomer = caller.role === "customer";
  if (isCustomer) {
    if (pending.customerUid !== request.auth.uid
        || status !== "fulfilled"
        || pending.status !== "ready") {
      throw new HttpsError("permission-denied", "This request cannot be updated by this account.");
    }
  } else if (caller.role !== "admin"
      && caller.role !== "owner"
      && caller.canCreateBills !== true
      && caller.canManageStock !== true) {
    throw new HttpsError("permission-denied", "This account cannot update stock requests.");
  }

  await requestRef.update({
    status,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.placeOrder = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const manualCustomerDocumentId = String(request.data?.manualCustomerDocumentId ?? "").trim();
  const customerUid = String(request.data?.customerUid
    ?? (manualCustomerDocumentId ? "" : request.auth?.uid ?? ""));
  const paymentMode = String(request.data?.paymentMode ?? "credit");
  const inputLines = request.data?.lines;

  if (!storeId || !Array.isArray(inputLines) || inputLines.length < 1 || inputLines.length > 50) {
    throw new HttpsError("invalid-argument", "The order has no valid items.");
  }
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in before placing an order.");
  }
  if (!new Set(["cash", "credit"]).has(paymentMode)) {
    throw new HttpsError("invalid-argument", "Choose cash or credit payment.");
  }

  const callerUid = request.auth.uid;
  const callerRef = storeMemberRef(storeId, callerUid);
  const customerRef = customerUid ? storeMemberRef(storeId, customerUid) : null;
  const manualCustomerRef = manualCustomerDocumentId
    ? db.doc(`stores/${storeId}/customers/${manualCustomerDocumentId}`)
    : null;
  const normalizedLines = inputLines.map((line) => ({
    productId: String(line?.productId ?? "").trim(),
    pieces: Number(line?.pieces),
  }));
  if (normalizedLines.some((line) => !line.productId || !Number.isInteger(line.pieces) || line.pieces < 1)) {
    throw new HttpsError("invalid-argument", "Each order line needs a product and a positive piece count.");
  }
  if (new Set(normalizedLines.map((line) => line.productId)).size !== normalizedLines.length) {
    throw new HttpsError("invalid-argument", "The order contains a duplicate product.");
  }

  const productRefs = normalizedLines.map((line) =>
    db.doc(`stores/${storeId}/products/${line.productId}`),
  );
  const orderRef = db.collection(`stores/${storeId}/orders`).doc();
  const billRef = db.collection(`stores/${storeId}/bills`).doc();
  const cartRef = db.doc(`stores/${storeId}/carts/${callerUid}`);

  return db.runTransaction(async (transaction) => {
    const profileRefs = [callerRef];
    if (!manualCustomerRef && customerUid && callerUid !== customerUid) {
      profileRefs.push(customerRef);
    }
    const profileSnapshots = await transaction.getAll(...profileRefs);
    const callerSnapshot = profileSnapshots[0];
    const customerSnapshot = manualCustomerRef
      ? null
      : customerUid === callerUid
        ? callerSnapshot
        : profileSnapshots[1];
    const manualCustomerSnapshot = manualCustomerRef
      ? await transaction.get(manualCustomerRef)
      : null;
    const productSnapshots = await transaction.getAll(...productRefs);

    if (!callerSnapshot.exists
        || (manualCustomerRef
          ? !manualCustomerSnapshot.exists
          : !customerSnapshot?.exists)) {
      throw new HttpsError("permission-denied", "The store account could not be verified.");
    }
    const caller = callerSnapshot.data();
    const callerRole = String(caller.role ?? "customer").trim().toLowerCase();
    const customer = manualCustomerRef
      ? manualCustomerSnapshot.data()
      : customerSnapshot.data();
    const isCustomerOrder = callerRole === "customer";
    if (isCustomerOrder && customerUid !== callerUid) {
      throw new HttpsError("permission-denied", "Customers can only order for their own account.");
    }
    if (!isCustomerOrder && !manualCustomerRef
        && String(customer.role ?? "").trim().toLowerCase() !== "customer") {
      throw new HttpsError("failed-precondition", "Choose a customer account for this sale.");
    }
    if (manualCustomerRef && isCustomerOrder) {
      throw new HttpsError("permission-denied", "Customers cannot create walk-in sales.");
    }
    if (!isCustomerOrder
        && callerRole !== "admin"
        && callerRole !== "owner"
        && caller.canCreateBills !== true) {
      throw new HttpsError("permission-denied", "This account cannot create orders.");
    }

    const lines = [];
    let total = 0;
    for (let index = 0; index < normalizedLines.length; index++) {
      const input = normalizedLines[index];
      const snapshot = productSnapshots[index];
      if (!snapshot.exists) {
        throw new HttpsError("not-found", `Product ${input.productId} was not found.`);
      }
      const product = snapshot.data();
      const stock = Number(product.stock);
      const price = Number(product.price);
      if (!Number.isFinite(price) || price <= 0 || !Number.isInteger(stock) || stock < input.pieces) {
        throw new HttpsError("failed-precondition", `There is not enough stock for ${product.name ?? input.productId}.`);
      }
      const lineTotal = price * input.pieces;
      total += lineTotal;
      lines.push({
        productId: snapshot.id,
        name: String(product.name ?? snapshot.id),
        quality: String(product.quality ?? ""),
        price,
        pieces: input.pieces,
        orderedPieces: input.pieces,
      });
    }

    for (let index = 0; index < normalizedLines.length; index++) {
      transaction.update(productRefs[index], {
        stock: productSnapshots[index].data().stock - normalizedLines[index].pieces,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const now = new Date();
    const orderCode = `ORD-${now.getTime()}-${orderRef.id.slice(0, 5).toUpperCase()}`;
    const billCode = `PJ-${now.getFullYear()}-${billRef.id.slice(0, 7).toUpperCase()}`;
    const payments = paymentMode === "cash"
      ? [{
          id: `PAY-${now.getTime()}`,
          amount: total,
          date: now,
          note: "Cash at order",
        }]
      : [];

    transaction.set(billRef, {
      id: billCode,
      customer: String(customer.name ?? "Customer"),
      customerId: String(customer.id ?? manualCustomerDocumentId ?? customerUid),
      customerUid,
      manualCustomerDocumentId: manualCustomerDocumentId || null,
      createdByUid: callerUid,
      createdByName: isCustomerOrder
        ? ""
        : String(caller.name ?? caller.email ?? "Store staff"),
      orderDocumentId: orderRef.id,
      createdAt: FieldValue.serverTimestamp(),
      lines,
      paymentMode,
      payments,
    });
    transaction.set(orderRef, {
      id: orderCode,
      customerId: String(customer.id ?? manualCustomerDocumentId ?? customerUid),
      customerUid,
      manualCustomerDocumentId: manualCustomerDocumentId || null,
      customerName: String(customer.name ?? "Customer"),
      placedByUid: callerUid,
      placedByName: String(caller.name ?? caller.email ?? "Store staff"),
      createdByRole: callerRole,
      createdAt: FieldValue.serverTimestamp(),
      billId: billCode,
      billDocumentId: billRef.id,
      lines,
      status: "received",
      seenByStaff: !isCustomerOrder,
    });
    transaction.delete(cartRef);

    return { orderId: orderCode, billId: billCode };
  });
});

exports.updateProductionTaskStatus = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const taskDocumentId = String(request.data?.taskDocumentId ?? "").trim();
  const status = String(request.data?.status ?? "");
  if (!storeId || !taskDocumentId
      || !new Set(["assigned", "inProgress", "completed"]).has(status)) {
    throw new HttpsError("invalid-argument", "The production task update is invalid.");
  }
  const caller = await requireCaller(request, storeId);
  const callerRole = String(caller.role ?? "").trim().toLowerCase();
  const isManager = callerRole === "admin" || callerRole === "owner";
  const taskRef = db.doc(`stores/${storeId}/productionTasks/${taskDocumentId}`);
  const taskSnapshot = await taskRef.get();
  if (!taskSnapshot.exists) {
    throw new HttpsError("not-found", "The production task was not found.");
  }
  const task = taskSnapshot.data();
  if (!isManager && task.workerUid !== request.auth.uid) {
    throw new HttpsError("permission-denied", "This task is assigned to another worker.");
  }
  const allowed = isManager
    || (task.status === "assigned" && status === "inProgress")
    || (task.status === "inProgress" && status === "completed");
  if (!allowed) {
    throw new HttpsError("failed-precondition", "Update the task one step at a time.");
  }
  await taskRef.update({ status, updatedAt: FieldValue.serverTimestamp() });
  return { ok: true };
});

exports.updateOrderStatus = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const orderDocumentId = String(request.data?.orderDocumentId ?? "").trim();
  const status = String(request.data?.status ?? "");
  if (!storeId || !orderDocumentId || !orderStatuses.has(status)) {
    throw new HttpsError("invalid-argument", "The order update is invalid.");
  }

  const caller = await requireCaller(request, storeId);
  if (caller.role !== "admin"
      && caller.role !== "owner"
      && caller.canCreateBills !== true) {
    throw new HttpsError("permission-denied", "This account cannot update orders.");
  }

  await db.doc(`stores/${storeId}/orders/${orderDocumentId}`).update({
    status,
    seenByStaff: true,
    statusUpdatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

exports.updateBillLinePrice = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const billDocumentId = String(request.data?.billDocumentId ?? "").trim();
  const lineIndex = Number(request.data?.lineIndex);
  const price = Number(request.data?.price);
  if (!storeId || !billDocumentId || !Number.isInteger(lineIndex)
      || !Number.isFinite(price) || price < 0) {
    throw new HttpsError("invalid-argument", "The bill price change is invalid.");
  }

  const caller = await requireCaller(request, storeId);
  if (caller.role !== "admin"
      && caller.role !== "owner"
      && caller.canCreateBills !== true) {
    throw new HttpsError("permission-denied", "This account cannot edit bill prices.");
  }

  const billRef = db.doc(`stores/${storeId}/bills/${billDocumentId}`);
  const billSnapshot = await billRef.get();
  if (!billSnapshot.exists) {
    throw new HttpsError("not-found", "The bill was not found.");
  }
  const bill = billSnapshot.data();
  let orderRef = bill.orderDocumentId
    ? db.doc(`stores/${storeId}/orders/${bill.orderDocumentId}`)
    : null;
  if (!orderRef) {
    const matchingOrder = await db.collection(`stores/${storeId}/orders`)
      .where("billDocumentId", "==", billDocumentId)
      .limit(1)
      .get();
    if (!matchingOrder.empty) orderRef = matchingOrder.docs[0].ref;
  }

  await db.runTransaction(async (transaction) => {
    const currentBillSnapshot = await transaction.get(billRef);
    if (!currentBillSnapshot.exists) {
      throw new HttpsError("not-found", "The bill was not found.");
    }
    const orderSnapshot = orderRef ? await transaction.get(orderRef) : null;
    const billData = currentBillSnapshot.data();
    const billLines = Array.isArray(billData.lines)
      ? billData.lines.map((line) => ({ ...line }))
      : [];
    if (lineIndex < 0 || lineIndex >= billLines.length) {
      throw new HttpsError("not-found", "The bill line was not found.");
    }
    billLines[lineIndex].price = price;
    transaction.update(billRef, {
      lines: billLines,
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (orderRef && orderSnapshot?.exists) {
      const orderLines = Array.isArray(orderSnapshot.data().lines)
        ? orderSnapshot.data().lines.map((line) => ({ ...line }))
        : [];
      const billLine = billLines[lineIndex];
      const orderLineIndex = orderLines[lineIndex]?.productId === billLine.productId
        ? lineIndex
        : orderLines.findIndex((line) => line.productId === billLine.productId);
      if (orderLineIndex >= 0) {
        orderLines[orderLineIndex].price = price;
        transaction.update(orderRef, {
          lines: orderLines,
          priceUpdatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  });
  return { ok: true };
});

exports.updateBillLineQuantity = onCall({ region }, async (request) => {
  const storeId = String(request.data?.storeId ?? "").trim();
  const billDocumentId = String(request.data?.billDocumentId ?? "").trim();
  const lineIndex = Number(request.data?.lineIndex);
  const pieces = Number(request.data?.pieces);
  if (!storeId || !billDocumentId || !Number.isInteger(lineIndex)
      || !Number.isInteger(pieces) || pieces < 0) {
    throw new HttpsError("invalid-argument", "The bill quantity change is invalid.");
  }

  const caller = await requireCaller(request, storeId);
  if (caller.role !== "admin"
      && caller.role !== "owner"
      && caller.canCreateBills !== true) {
    throw new HttpsError("permission-denied", "This account cannot edit bill quantities.");
  }

  const billRef = db.doc(`stores/${storeId}/bills/${billDocumentId}`);
  const initialBillSnapshot = await billRef.get();
  if (!initialBillSnapshot.exists) {
    throw new HttpsError("not-found", "The bill was not found.");
  }
  const initialBill = initialBillSnapshot.data();
  let orderRef = initialBill.orderDocumentId
    ? db.doc(`stores/${storeId}/orders/${initialBill.orderDocumentId}`)
    : null;
  if (!orderRef) {
    const matchingOrder = await db.collection(`stores/${storeId}/orders`)
      .where("billDocumentId", "==", billDocumentId)
      .limit(1)
      .get();
    if (!matchingOrder.empty) orderRef = matchingOrder.docs[0].ref;
  }

  await db.runTransaction(async (transaction) => {
    const billSnapshot = await transaction.get(billRef);
    if (!billSnapshot.exists) {
      throw new HttpsError("not-found", "The bill was not found.");
    }
    const orderSnapshot = orderRef ? await transaction.get(orderRef) : null;
    const bill = billSnapshot.data();
    const lines = Array.isArray(bill.lines) ? bill.lines.map((line) => ({ ...line })) : [];
    if (lineIndex < 0 || lineIndex >= lines.length) {
      throw new HttpsError("not-found", "The bill line was not found.");
    }
    const line = lines[lineIndex];
    const oldPieces = Number(line.pieces);
    const orderedPieces = Number(line.orderedPieces ?? line.pieces);
    if (!Number.isInteger(oldPieces) || !Number.isInteger(orderedPieces)
        || orderedPieces < oldPieces || pieces > orderedPieces) {
      throw new HttpsError("failed-precondition", "The bill quantity must be between zero and the original ordered quantity.");
    }
    if (pieces === oldPieces) return;

    const pendingId = `bill-${billDocumentId}-${lineIndex}`;
    const pendingRef = db.doc(`stores/${storeId}/pendingRequests/${pendingId}`);
    const productRef = db.doc(`stores/${storeId}/products/${String(line.productId ?? "")}`);
    const productSnapshot = await transaction.get(productRef);
    const pendingSnapshot = await transaction.get(pendingRef);
    if (!productSnapshot.exists) {
      throw new HttpsError("not-found", "The product for this bill line was not found.");
    }
    if (pendingSnapshot.exists && pendingSnapshot.data().status === "fulfilled") {
      throw new HttpsError("failed-precondition", "This bill's pending quantity was already fulfilled. Edit the follow-up sale instead.");
    }

    const product = productSnapshot.data();
    const stockDelta = oldPieces - pieces;
    const nextStock = Number(product.stock) + stockDelta;
    if (nextStock < 0) {
      throw new HttpsError("failed-precondition", "There is not enough stock to increase this bill quantity.");
    }
    line.orderedPieces = orderedPieces;
    line.pieces = pieces;
    const currentTotal = lines.reduce((total, billLine) =>
      total + Number(billLine.price ?? 0) * Number(billLine.pieces ?? 0), 0);
    const paid = (bill.payments ?? []).reduce((total, payment) =>
      total + Number(payment.amount ?? 0), 0);
    if (paid > currentTotal + 0.001) {
      throw new HttpsError("failed-precondition", "The new bill total is below the amount already paid.");
    }

    transaction.update(productRef, {
      stock: nextStock,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(billRef, {
      lines,
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (orderRef && orderSnapshot?.exists) {
      const orderData = orderSnapshot.data();
      const orderLines = Array.isArray(orderData.lines)
        ? orderData.lines.map((orderLine) => ({ ...orderLine }))
        : [];
      const orderLineIndex = orderLines[lineIndex]?.productId === line.productId
        ? lineIndex
        : orderLines.findIndex((orderLine) => orderLine.productId === line.productId);
      if (orderLineIndex >= 0) {
        orderLines[orderLineIndex].orderedPieces = orderedPieces;
        orderLines[orderLineIndex].pieces = pieces;
        transaction.update(orderRef, {
          lines: orderLines,
          quantityUpdatedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    const remaining = orderedPieces - pieces;
    if (remaining > 0) {
      const priorPending = pendingSnapshot.exists ? pendingSnapshot.data() : {};
      transaction.set(pendingRef, {
        id: pendingId,
        customerUid: String(bill.customerUid ?? ""),
        customerId: String(bill.customerId ?? ""),
        customerName: String(bill.customer ?? "Customer"),
        productId: String(line.productId ?? ""),
        productName: String(line.name ?? product.name ?? "Product"),
        quality: String(line.quality ?? product.quality ?? ""),
        pricePerPiece: Number(line.price ?? product.price ?? 0),
        pieces: remaining,
        originBillDocumentId: billDocumentId,
        createdAt: priorPending.createdAt ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        status: "pending",
      });
    } else if (pendingSnapshot.exists) {
      transaction.delete(pendingRef);
    }
  });
  return { ok: true };
});

exports.notifyStaffOfNewOrder = onDocumentCreated(
  {
    document: "stores/{storeId}/orders/{orderDocumentId}",
    region,
  },
  async (event) => {
    const order = event.data?.data();
    if (!order) return;

    const storeId = event.params.storeId;
    const isCustomerOrder = order.createdByRole === "customer"
      || (order.createdByRole == null && order.placedByUid === order.customerUid);
    let memberRefs;
    if (isCustomerOrder) {
      const staff = await db.collection(`stores/${storeId}/members`)
        .where("role", "in", ["admin", "owner", "employee"])
        .get();
      memberRefs = staff.docs.map((member) => member.ref);
    } else if (order.customerUid) {
      memberRefs = [storeMemberRef(storeId, order.customerUid)];
    } else {
      return;
    }
    const tokenSnapshots = await Promise.all(
      memberRefs.map((member) => member.collection("tokens").get()),
    );
    const tokenRefs = new Map();
    for (const snapshot of tokenSnapshots) {
      for (const tokenDoc of snapshot.docs) {
        const token = String(tokenDoc.data().token ?? "").trim();
        if (token) tokenRefs.set(token, tokenDoc.ref);
      }
    }
    const entries = [...tokenRefs.entries()];
    if (entries.length === 0) return;

    const itemCount = (order.lines ?? []).reduce((sum, line) => sum + Number(line.pieces ?? 0), 0);
    const title = isCustomerOrder ? "New jewellery order" : "Your order has been placed";
    const body = isCustomerOrder
      ? `${order.customerName ?? order.placedByName ?? "A customer"} placed order ${order.id ?? event.params.orderDocumentId} (${itemCount} pieces).`
      : `${order.placedByName ?? "Store staff"} placed order ${order.id ?? event.params.orderDocumentId} for you (${itemCount} pieces).`;
    for (let offset = 0; offset < entries.length; offset += 500) {
      const chunk = entries.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map(([token]) => token),
        notification: { title, body },
        data: {
          type: "new_order",
          storeId,
          orderDocumentId: event.params.orderDocumentId,
          orderId: String(order.id ?? event.params.orderDocumentId),
          customerName: String(order.customerName ?? "Customer"),
          placedByName: String(order.placedByName ?? "Customer"),
        },
        android: {
          priority: "high",
          notification: { channelId: "orders", sound: "default" },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });

      const removals = [];
      response.responses.forEach((result, index) => {
        const code = result.error?.code ?? "";
        if (code.includes("registration-token-not-registered")
            || code.includes("invalid-registration-token")) {
          removals.push(chunk[index][1].delete());
        }
      });
      await Promise.all(removals);
    }
  },
);

exports.notifyWorkerOfProductionTask = onDocumentCreated(
  {
    document: "stores/{storeId}/productionTasks/{taskDocumentId}",
    region,
  },
  async (event) => {
    const task = event.data?.data();
    const workerUid = String(task?.workerUid ?? "").trim();
    if (!task || !workerUid) return;
    const tokens = await storeMemberRef(event.params.storeId, workerUid)
      .collection("tokens")
      .get();
    const tokenRefs = new Map();
    for (const tokenDoc of tokens.docs) {
      const token = String(tokenDoc.data().token ?? "").trim();
      if (token) tokenRefs.set(token, tokenDoc.ref);
    }
    const entries = [...tokenRefs.entries()];
    if (entries.length === 0) return;

    const title = "Production work assigned";
    const body = `${task.productName ?? task.productId}: make ${Number(task.piecesToMake ?? 0)} pieces. Current stock: ${Number(task.currentStock ?? 0)}.`;
    for (let offset = 0; offset < entries.length; offset += 500) {
      const chunk = entries.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: chunk.map(([token]) => token),
        notification: { title, body },
        data: {
          type: "production_task",
          storeId: event.params.storeId,
          taskDocumentId: event.params.taskDocumentId,
          productId: String(task.productId ?? ""),
          currentStock: String(task.currentStock ?? 0),
          piecesToMake: String(task.piecesToMake ?? 0),
        },
        android: {
          priority: "high",
          notification: { channelId: "orders", sound: "default" },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });
      const removals = [];
      response.responses.forEach((result, index) => {
        const code = result.error?.code ?? "";
        if (code.includes("registration-token-not-registered")
            || code.includes("invalid-registration-token")) {
          removals.push(chunk[index][1].delete());
        }
      });
      await Promise.all(removals);
    }
  },
);
