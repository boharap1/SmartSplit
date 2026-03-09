import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScannedReceiptData {
  final String? merchantName;
  final double? totalAmount;
  final DateTime? date;
  final String rawText;
  final List<String> lineItems;

  ScannedReceiptData({
    this.merchantName,
    this.totalAmount,
    this.date,
    required this.rawText,
    this.lineItems = const [],
  });

  bool get hasData => merchantName != null || totalAmount != null || date != null;
}

class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<ScannedReceiptData> scanReceipt(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      final String rawText = recognizedText.text;
      final List<String> lines = rawText.split('\n').where((line) => line.trim().isNotEmpty).toList();

      // Extract data from recognized text
      final double? amount = _extractTotalAmount(rawText, lines);
      final String? merchant = _extractMerchantName(lines);
      final DateTime? date = _extractDate(rawText);

      return ScannedReceiptData(
        merchantName: merchant,
        totalAmount: amount,
        date: date,
        rawText: rawText,
        lineItems: lines,
      );
    } catch (e) {
      return ScannedReceiptData(
        rawText: 'Error scanning receipt: ${e.toString()}',
        lineItems: [],
      );
    }
  }

  double? _extractTotalAmount(String text, List<String> lines) {
    // Common total keywords
    final totalKeywords = [
      'total',
      'grand total',
      'amount due',
      'balance due',
      'total due',
      'subtotal',
      'amount',
      'sum',
      'to pay',
    ];

    // Try to find total amount near keywords
    for (final line in lines.reversed) {
      final lowerLine = line.toLowerCase();
      
      for (final keyword in totalKeywords) {
        if (lowerLine.contains(keyword)) {
          final amount = _extractAmountFromLine(line);
          if (amount != null && amount > 0) {
            return amount;
          }
        }
      }
    }

    // If no keyword found, try to find the largest amount (likely the total)
    double? largestAmount;
    for (final line in lines) {
      final amount = _extractAmountFromLine(line);
      if (amount != null && (largestAmount == null || amount > largestAmount)) {
        largestAmount = amount;
      }
    }

    return largestAmount;
  }

  double? _extractAmountFromLine(String line) {
    // Match currency patterns: £10.99, $10.99, 10.99, 10,99
    final patterns = [
      RegExp(r'[£$€]\s*(\d+[.,]\d{2})'),      // £10.99
      RegExp(r'(\d+[.,]\d{2})\s*[£$€]'),      // 10.99£
      RegExp(r'(\d+[.,]\d{2})(?!\d)'),         // 10.99 (at end or followed by non-digit)
      RegExp(r'(\d+)[.,](\d{2})'),             // 10.99 or 10,99
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        String amountStr = match.group(1) ?? match.group(0) ?? '';
        // Remove currency symbols and normalize
        amountStr = amountStr.replaceAll(RegExp(r'[£$€\s]'), '');
        amountStr = amountStr.replaceAll(',', '.');
        
        final amount = double.tryParse(amountStr);
        if (amount != null && amount > 0 && amount < 100000) {
          return amount;
        }
      }
    }

    return null;
  }

  String? _extractMerchantName(List<String> lines) {
    if (lines.isEmpty) return null;

    // Usually the merchant name is in the first few lines
    // Skip very short lines or lines that look like addresses/dates
    for (int i = 0; i < lines.length && i < 5; i++) {
      final line = lines[i].trim();
      
      // Skip if too short
      if (line.length < 3) continue;
      
      // Skip if looks like a date
      if (RegExp(r'\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}').hasMatch(line)) continue;
      
      // Skip if looks like a phone number
      if (RegExp(r'^\+?\d[\d\s\-]{8,}$').hasMatch(line)) continue;
      
      // Skip if looks like an address (contains common address words)
      if (RegExp(r'(street|road|lane|avenue|drive|st\.|rd\.|ave\.)', caseSensitive: false).hasMatch(line)) continue;
      
      // Skip if mostly numbers
      final digitCount = line.replaceAll(RegExp(r'[^0-9]'), '').length;
      if (digitCount > line.length / 2) continue;

      // This line is likely the merchant name
      return line;
    }

    return lines.isNotEmpty ? lines.first : null;
  }

  DateTime? _extractDate(String text) {
    // Common date patterns
    final datePatterns = [
      // DD/MM/YYYY or DD-MM-YYYY
      RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})'),
      // DD/MM/YY or DD-MM-YY
      RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{2})(?!\d)'),
      // YYYY-MM-DD
      RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})'),
    ];

    for (final pattern in datePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        try {
          int day, month, year;
          
          if (match.group(1)!.length == 4) {
            // YYYY-MM-DD format
            year = int.parse(match.group(1)!);
            month = int.parse(match.group(2)!);
            day = int.parse(match.group(3)!);
          } else {
            // DD/MM/YYYY or DD/MM/YY format
            day = int.parse(match.group(1)!);
            month = int.parse(match.group(2)!);
            year = int.parse(match.group(3)!);
            
            // Handle 2-digit year
            if (year < 100) {
              year += (year > 50) ? 1900 : 2000;
            }
          }

          // Validate date
          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            final date = DateTime(year, month, day);
            // Only accept dates within reasonable range
            if (date.isBefore(DateTime.now().add(const Duration(days: 1))) &&
                date.isAfter(DateTime(2020))) {
              return date;
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}