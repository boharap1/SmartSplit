import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/bank_details_model.dart';
import '../../services/settlement_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_button.dart';

class BankDetailsScreen extends StatefulWidget {
  final String userId;
  final BankDetails? existingDetails;

  const BankDetailsScreen({
    super.key,
    required this.userId,
    this.existingDetails,
  });

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountHolderController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _sortCodeController = TextEditingController();
  final _accountNumberController = TextEditingController();

  final SettlementService _settlementService = SettlementService();
  bool _isLoading = false;
  bool _obscureAccountNumber = true;

  @override
  void initState() {
    super.initState();
    if (widget.existingDetails != null) {
      _accountHolderController.text = widget.existingDetails!.accountHolderName;
      _bankNameController.text = widget.existingDetails!.bankName;
      _sortCodeController.text = widget.existingDetails!.sortCode;
      _accountNumberController.text = widget.existingDetails!.accountNumber;
    }
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _sortCodeController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  String? _validateSortCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter sort code';
    }
    final clean = value.replaceAll('-', '').replaceAll(' ', '');
    if (clean.length != 6 || int.tryParse(clean) == null) {
      return 'Sort code must be 6 digits';
    }
    return null;
  }

  String? _validateAccountNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter account number';
    }
    final clean = value.replaceAll(' ', '');
    if (clean.length < 8 || clean.length > 10 || int.tryParse(clean) == null) {
      return 'Account number must be 8-10 digits';
    }
    return null;
  }

  Future<void> _saveBankDetails() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final bankDetails = BankDetails(
      accountHolderName: _accountHolderController.text.trim(),
      bankName: _bankNameController.text.trim(),
      sortCode: _sortCodeController.text.replaceAll('-', '').replaceAll(' ', ''),
      accountNumber: _accountNumberController.text.replaceAll(' ', ''),
      updatedAt: DateTime.now(),
    );

    final result = await _settlementService.saveBankDetails(
      userId: widget.userId,
      bankDetails: bankDetails,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bank details saved securely'),
            backgroundColor: AppConstants.successColor,
          ),
        );
        Navigator.pop(context, bankDetails);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to save'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Bank Details'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your data is secure',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          Text(
                            'Bank details are encrypted and only visible to group members for settlements.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _accountHolderController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Account Holder Name',
                  hintText: 'Enter name as shown on account',
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter account holder name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _bankNameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g., Barclays, HSBC, Lloyds',
                  prefixIcon: const Icon(Icons.account_balance),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter bank name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _sortCodeController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: 'Sort Code',
                  hintText: '000000',
                  prefixIcon: const Icon(Icons.tag),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  ),
                ),
                validator: _validateSortCode,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _accountNumberController,
                obscureText: _obscureAccountNumber,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  hintText: '12345678',
                  prefixIcon: const Icon(Icons.numbers),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureAccountNumber ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() => _obscureAccountNumber = !_obscureAccountNumber);
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                  ),
                ),
                validator: _validateAccountNumber,
              ),
              const SizedBox(height: 32),

              CustomButton(
                text: widget.existingDetails != null ? 'Update Bank Details' : 'Save Bank Details',
                onPressed: _isLoading ? null : _saveBankDetails,
                isLoading: _isLoading,
                icon: Icons.save,
              ),
              const SizedBox(height: 16),

              Text(
                'These details will be shown to group members when they need to pay you.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}