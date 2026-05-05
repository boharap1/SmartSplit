import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC encryption for bank details stored in Firestore.
///
/// Key = SHA-256(pepper + userId) — derived at runtime, never stored.
/// Each save generates a fresh random IV so ciphertexts differ even for
/// identical inputs.
///
/// Stored Firestore shape:
///   { _enc: true, _iv: "base64", _d: "base64", bankName: "...", updatedAt: ... }
///
/// Falls back transparently if the stored data is pre-encryption plaintext,
/// so existing records continue to work until the user saves again.
class BankDetailsEncryption {
  static const _pepper = 'SS_BankEnc_2024_v1';

  static enc.Key _key(String userId) {
    final bytes = sha256.convert(utf8.encode('$_pepper:$userId')).bytes;
    return enc.Key(Uint8List.fromList(bytes));
  }

  /// Encrypts accountNumber, sortCode, accountHolderName into a single blob.
  /// bankName and updatedAt are not sensitive and remain plaintext.
  static Map<String, dynamic> encrypt(
      Map<String, dynamic> plain, String userId) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key(userId)));

    final payload = jsonEncode({
      'accountNumber': plain['accountNumber'],
      'sortCode': plain['sortCode'],
      'accountHolderName': plain['accountHolderName'],
    });

    final cipher = encrypter.encrypt(payload, iv: iv);

    return {
      'bankName': plain['bankName'],
      'updatedAt': plain['updatedAt'],
      '_enc': true,
      '_iv': iv.base64,
      '_d': cipher.base64,
    };
  }

  /// Decrypts a stored bank details map.
  /// If the map has no `_enc` flag (legacy plaintext record) it is returned
  /// unchanged so the user can still read their data before saving again.
  static Map<String, dynamic> decrypt(
      Map<String, dynamic> stored, String userId) {
    if (stored['_enc'] != true) return stored;

    try {
      final iv = enc.IV.fromBase64(stored['_iv'] as String);
      final encrypter = enc.Encrypter(enc.AES(_key(userId)));
      final plain = encrypter.decrypt64(stored['_d'] as String, iv: iv);
      final sensitive = jsonDecode(plain) as Map<String, dynamic>;
      return {
        ...sensitive,
        'bankName': stored['bankName'],
        'updatedAt': stored['updatedAt'],
      };
    } catch (_) {
      // Decryption failure — return stored data rather than crash.
      return stored;
    }
  }
}
