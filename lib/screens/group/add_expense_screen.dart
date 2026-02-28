import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;

  const AddExpenseScreen({super.key, required this.group});

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

    try {
      final result = await context.read<ExpenseProvider>().createEqualSplitExpense(
        groupId: widget.group.groupId,
        description: _descriptionController.text.trim(),
        totalAmount: amount,
        paidBy: _selectedPayer!,
        participantIds: _selectedParticipants,
        category: _selectedCategory,
        date: _selectedDate,
        createdBy: currentUserId!,
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
        Navigator.pop(context);
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
                    // Description
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

                    // Amount
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

                    // Date picker
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

                    // Category
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

                    // Paid by
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

                    // Split between
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

                    // Split preview
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

                    // Add button
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