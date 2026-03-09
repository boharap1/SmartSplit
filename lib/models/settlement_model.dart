import 'package:cloud_firestore/cloud_firestore.dart';

enum SettlementStatus {
  pending,
  confirmed,
  completed,
  disputed,
}

class SettlementRecord {
  final String settlementId;
  final String groupId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final SettlementStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String? paymentMethod;
  final String? paymentReference;
  final String? note;

  SettlementRecord({
    required this.settlementId,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    this.paymentMethod,
    this.paymentReference,
    this.note,
  });

  factory SettlementRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SettlementRecord(
      settlementId: doc.id,
      groupId: data['groupId'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      toUserId: data['toUserId'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      status: SettlementStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => SettlementStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      confirmedAt: data['confirmedAt'] != null
          ? (data['confirmedAt'] as Timestamp).toDate()
          : null,
      paymentMethod: data['paymentMethod'],
      paymentReference: data['paymentReference'],
      note: data['note'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'amount': amount,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'note': note,
    };
  }
}