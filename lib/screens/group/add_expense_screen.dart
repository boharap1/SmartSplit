import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../services/receipt_scanner_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final String? currentUserId;
  final ScannedReceiptData? scannedData;

  const AddExpenseScreen({
    super.key,
    required this.group,
    this.currentUserId,
    this.scannedData,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

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
    _selectedPayer = context.read<AuthProvider>().firebaseUser?.uid;
    _selectedParticipants = List.from(widget.group.members);

    if (widget.scannedData != null) {
      if (widget.scannedData!.merchantName != null) {
        _descriptionController.text = widget.scannedData!.merchantName!;
      }
      if (widget.scannedData!.totalAmount != null) {
        _amountController.text = widget.scannedData!.totalAmount!
            .toStringAsFixed(2);
      }
      if (widget.scannedData!.date != null) {
        _selectedDate = widget.scannedData!.date!;
      }
    }

    _fetchMemberDetails();
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
      } else {
        final Map<String, UserModel> cache = {};
        for (int i = 0; i < memberIds.length; i += 10) {
          final chunk = memberIds.sublist(
            i,
            (i + 10 > memberIds.length) ? memberIds.length : i + 10,
          );
          final snapshot = await firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();

          for (final doc in snapshot.docs) {
            cache[doc.id] = UserModel.fromFirestore(doc);
          }
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppConstants.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
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

    final currentUserId = context.read<AuthProvider>().firebaseUser?.uid;
    final amount = double.parse(_amountController.text.trim());

    final result = await context
        .read<ExpenseProvider>()
        .createEqualSplitExpense(
          groupId: widget.group.groupId,
          description: _descriptionController.text.trim(),
          totalAmount: amount,
          paidBy: _selectedPayer!,
          participantIds: _selectedParticipants,
          category: _selectedCategory,
          date: _selectedDate,
          createdBy: currentUserId!,
        );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result.expense != null) {
        Navigator.pop(context, widget.group.groupName);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to add expense'),
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
        title: const Text('Add Expense'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingMembers
          ? const Center(
              child: CircularProgressIndicator(
                color: AppConstants.primaryColor,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.scannedData != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(
                            AppConstants.borderRadius,
                          ),
                          border: Border.all(
                            color: AppConstants.successColor.withOpacity(0.4),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: AppConstants.successColor,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Fields pre-filled from scanned receipt',
                              style: TextStyle(
                                color: AppConstants.successColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                          borderRadius: BorderRadius.circular(
                            AppConstants.borderRadius,
                          ),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppConstants.borderRadius,
                        ),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          hint: const Row(
                            children: [
                              Icon(Icons.category_outlined, color: Colors.grey),
                              SizedBox(width: 12),
                              Text('Select Category (Optional)'),
                            ],
                          ),
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

                    const Text(
                      'Paid by',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppConstants.borderRadius,
                        ),
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
                        const Text(
                          'Split between',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedParticipants.length ==
                                  widget.group.members.length) {
                                _selectedParticipants = [];
                              } else {
                                _selectedParticipants = List.from(
                                  widget.group.members,
                                );
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
                        borderRadius: BorderRadius.circular(
                          AppConstants.borderRadius,
                        ),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: widget.group.members.map((memberId) {
                          final isSelected = _selectedParticipants.contains(
                            memberId,
                          );
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
                              double.tryParse(_amountController.text.trim()) ??
                              0;
                          final perPerson =
                              amount / _selectedParticipants.length;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                AppConstants.borderRadius,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: AppConstants.primaryColor,
                                ),
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
                      onPressed: _handleAddExpense,
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
