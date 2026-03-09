import 'package:cloud_firestore/cloud_firestore.dart';

class BankDetails {
  final String accountHolderName;
  final String bankName;
  final String sortCode;
  final String accountNumber;
  final DateTime updatedAt;

  BankDetails({
    required this.accountHolderName,
    required this.bankName,
    required this.sortCode,
    required this.accountNumber,
    required this.updatedAt,
  });

  factory BankDetails.fromMap(Map<String, dynamic> data) {
    return BankDetails(
      accountHolderName: data['accountHolderName'] ?? '',
      bankName: data['bankName'] ?? '',
      sortCode: data['sortCode'] ?? '',
      accountNumber: data['accountNumber'] ?? '',
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'accountHolderName': accountHolderName,
      'bankName': bankName,
      'sortCode': sortCode,
      'accountNumber': accountNumber,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  String get maskedAccountNumber {
    if (accountNumber.length <= 4) return accountNumber;
    return '****${accountNumber.substring(accountNumber.length - 4)}';
  }

  String get formattedSortCode {
    final clean = sortCode.replaceAll('-', '');
    if (clean.length != 6) return sortCode;
    return '${clean.substring(0, 2)}-${clean.substring(2, 4)}-${clean.substring(4, 6)}';
  }

  bool get isComplete {
    return accountHolderName.isNotEmpty &&
        bankName.isNotEmpty &&
        sortCode.replaceAll('-', '').length == 6 &&
        accountNumber.length >= 8;
  }
}