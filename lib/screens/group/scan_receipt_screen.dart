import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/group_model.dart';
import '../../services/receipt_scanner_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_button.dart';
import 'add_expense_screen.dart';

class ScanReceiptScreen extends StatefulWidget {
  final GroupModel group;
  final String currentUserId;

  const ScanReceiptScreen({
    super.key,
    required this.group,
    required this.currentUserId,
  });

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ReceiptScannerService _scannerService = ReceiptScannerService();

  File? _selectedImage;
  ScannedReceiptData? _scannedData;
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void dispose() {
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _scannedData = null;
          _errorMessage = null;
        });
        await _scanReceipt();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image: ${e.toString()}';
      });
    }
  }

  Future<void> _scanReceipt() async {
    if (_selectedImage == null) return;

    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final data = await _scannerService.scanReceipt(_selectedImage!);
      setState(() {
        _scannedData = data;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to scan receipt: ${e.toString()}';
        _isScanning = false;
      });
    }
  }

  Future<void> _useScannedData() async {
    if (_scannedData == null) return;

    final groupName = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          group: widget.group,
          currentUserId: widget.currentUserId,
          scannedData: _scannedData,
        ),
      ),
    );
    if (groupName != null && mounted) {
      Navigator.pop(context, groupName);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.defaultPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Image Source',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppConstants.primaryColor,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo of the receipt'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[600],
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from your photos'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview area
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No receipt selected',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the button below to scan a receipt',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 20),

            // Scan button
            CustomButton(
              text: _selectedImage == null ? 'Select Receipt Image' : 'Change Image',
              onPressed: _showImageSourceDialog,
              icon: Icons.add_a_photo,
            ),
            const SizedBox(height: 20),

            // Scanning indicator
            if (_isScanning)
              Container(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppConstants.primaryColor,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Scanning receipt...',
                      style: TextStyle(
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                decoration: BoxDecoration(
                  color: AppConstants.errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppConstants.errorColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppConstants.errorColor),
                      ),
                    ),
                  ],
                ),
              ),

            // Scanned data preview
            if (_scannedData != null && !_isScanning) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppConstants.successColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Extracted Data',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildDataRow(
                      'Merchant',
                      _scannedData!.merchantName ?? 'Not detected',
                      _scannedData!.merchantName != null,
                    ),
                    _buildDataRow(
                      'Amount',
                      _scannedData!.totalAmount != null
                          ? '£${_scannedData!.totalAmount!.toStringAsFixed(2)}'
                          : 'Not detected',
                      _scannedData!.totalAmount != null,
                    ),
                    _buildDataRow(
                      'Date',
                      _scannedData!.date != null
                          ? '${_scannedData!.date!.day}/${_scannedData!.date!.month}/${_scannedData!.date!.year}'
                          : 'Not detected',
                      _scannedData!.date != null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Use data button
              CustomButton(
                text: 'Use This Data',
                onPressed: _useScannedData,
                icon: Icons.arrow_forward,
              ),
              const SizedBox(height: 12),

              // View raw text button
              TextButton.icon(
                onPressed: () => _showRawTextDialog(),
                icon: const Icon(Icons.text_snippet),
                label: const Text('View Raw Text'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, bool detected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: detected ? Colors.black : Colors.grey,
              ),
            ),
          ),
          Icon(
            detected ? Icons.check : Icons.close,
            size: 18,
            color: detected ? AppConstants.successColor : Colors.grey,
          ),
        ],
      ),
    );
  }

  void _showRawTextDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raw Scanned Text'),
        content: SingleChildScrollView(
          child: Text(
            _scannedData?.rawText ?? 'No text detected',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}