import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/expense_model.dart';
import '../../services/expense_service.dart';
import '../../services/receipt_scanner_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';
import 'scan_receipt_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final String currentUserId;
  final ScannedReceiptData? scannedData;

  const AddExpenseScreen({
    super.key,
    required this.group,
    required this.currentUserId,
    this.scannedData,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final ExpenseService _expenseService = ExpenseService();

  String? _selectedPayer;
  List<String> _selectedParticipants = [];
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  bool _isLoading = false;

  Map<String, UserModel> _memberCache = {};
  bool _isLoadingMembers = true;

  final List<String> _categories = [
    'Food & Drinks',
    'Transport',
    'Accommodation',
    'Entertainment',
    'Shopping',
    'Utilities',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _selectedPayer = widget.currentUserId;
    _selectedParticipants = List.from(widget.group.members);
    _fetchMemberDetails();
    _applyScannedData();
  }

  void _applyScannedData() {
    if (widget.scannedData != null) {
      final data = widget.scannedData!;

      if (data.merchantName != null) {
        _descriptionController.text = data.merchantName!;
      }

      if (data.totalAmount != null) {
        _amountController.text = data.totalAmount!.toStringAsFixed(2);
      }

      if (data.date != null) {
        _selectedDate = data.date!;
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchMemberDetails() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final memberIds = widget.group.members;

      if (memberIds.length <= 10) {
        final snapshot = await firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: memberIds)
            .get();

        final Map<String, UserModel> cache = {};
        for (final doc in snapshot.docs) {
          cache[doc.id] = UserModel.fromFirestore(doc);
        }

        if (mounted) {
          setState(() {
            _memberCache = cache;
            _isLoadingMembers = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  String _getMemberName(String userId) {
    return _memberCache[userId]?.name ?? 'Unknown';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _navigateToScanReceipt() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ScanReceiptScreen(
          group: widget.group,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  Future<void> _handleAddExpense() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select who paid'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    if (_selectedParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one participant'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final amount = double.parse(_amountController.text.trim());
    final splitAmount = amount / _selectedParticipants.length;

    final splits = _selectedParticipants
        .map((userId) => ExpenseSplit(
              userId: userId,
              amount: double.parse(splitAmount.toStringAsFixed(2)),
            ))
        .toList();

    try {
      final result = await _expenseService.createExpense(
        groupId: widget.group.groupId,
        description: _descriptionController.text.trim(),
        totalAmount: amount,
        paidBy: _selectedPayer!,
        splits: splits,
        splitType: SplitType.equal,
        category: _selectedCategory,
        date: _selectedDate,
        createdBy: widget.currentUserId,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result.expense != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expense added successfully!'),
            backgroundColor: AppConstants.successColor,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to add expense'),
            backgroundColor: AppConstants.errorColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppConstants.errorColor,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Add Expense'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _navigateToScanReceipt,
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Scan Receipt',
          ),
        ],
      ),
      body: _isLoadingMembers
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Scanned data indicator
                    if (widget.scannedData != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppConstants.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                          border: Border.all(color: AppConstants.successColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.document_scanner, color: AppConstants.successColor),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Data auto-filled from scanned receipt',
                                style: TextStyle(color: AppConstants.successColor),
                              ),
                            ),
                            TextButton(
                              onPressed: _navigateToScanReceipt,
                              child: const Text('Rescan'),
                            ),
                          ],
                        ),
                      ),

                    // Scan Receipt Button (if no scanned data)
                    if (widget.scannedData == null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: OutlinedButton.icon(
                          onPressed: _navigateToScanReceipt,
                          icon: const Icon(Icons.document_scanner),
                          label: const Text('Scan Receipt with AI'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            side: const BorderSide(color: AppConstants.primaryColor),
                          ),
                        ),
                      ),

                    CustomTextField(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'What was this expense for?',
                      prefixIcon: Icons.description_outlined,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    CustomTextField(
                      controller: _amountController,
                      label: 'Amount (£)',
                      hint: '0.00',
                      prefixIcon: Icons.currency_pound,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an amount';
                        }
                        final amount = double.tryParse(value.trim());
                        if (amount == null || amount <= 0) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppConstants.borderRadius),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.grey),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Date',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600])),
                                Text(
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          hint: const Text('Select Category (Optional)'),
                          isExpanded: true,
                          items: _categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedCategory = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text('Paid by',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: widget.group.members.map((memberId) {
                          return RadioListTile<String>(
                            value: memberId,
                            groupValue: _selectedPayer,
                            title: Text(_getMemberName(memberId)),
                            activeColor: AppConstants.primaryColor,
                            onChanged: (value) {
                              setState(() => _selectedPayer = value);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Split between',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedParticipants.length ==
                                  widget.group.members.length) {
                                _selectedParticipants = [];
                              } else {
                                _selectedParticipants =
                                    List.from(widget.group.members);
                              }
                            });
                          },
                          child: Text(
                            _selectedParticipants.length ==
                                    widget.group.members.length
                                ? 'Deselect All'
                                : 'Select All',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: widget.group.members.map((memberId) {
                          final isSelected =
                              _selectedParticipants.contains(memberId);
                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(_getMemberName(memberId)),
                            activeColor: AppConstants.primaryColor,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedParticipants.add(memberId);
                                } else {
                                  _selectedParticipants.remove(memberId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_selectedParticipants.isNotEmpty &&
                        _amountController.text.isNotEmpty)
                      Builder(
                        builder: (context) {
                          final amount =
                              double.tryParse(_amountController.text.trim()) ?? 0;
                          final perPerson =
                              amount / _selectedParticipants.length;
                          return Container(
                            padding:
                                const EdgeInsets.all(AppConstants.defaultPadding),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.borderRadius),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: AppConstants.primaryColor),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '£${perPerson.toStringAsFixed(2)} per person (${_selectedParticipants.length} people)',
                                    style: const TextStyle(
                                      color: AppConstants.primaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 32),

                    CustomButton(
                      text: 'Add Expense',
                      onPressed: _isLoading ? null : _handleAddExpense,
                      isLoading: _isLoading,
                      icon: Icons.add,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}