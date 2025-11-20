import 'package:flutter/material.dart' hide TextStyle, Colors, BorderRadius;
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import 'package:flutter/painting.dart' show TextStyle, BorderRadius;
import 'package:flutter/material.dart' show Colors;

class LendBorrowScreen extends StatefulWidget {
  const LendBorrowScreen({super.key});

  @override
  State<LendBorrowScreen> createState() => _LendBorrowScreenState();
}

class _LendBorrowScreenState extends State<LendBorrowScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Lend & Borrow',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBorder
                    : AppColors.border,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              labelColor: Theme.of(context).brightness == Brightness.dark ? AppColors.primary : Colors.white,
              unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('I Gave'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_downward_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('I Took'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          return TabBarView(
            controller: _tabController,
            children: [
              _buildLendGivenTab(dataProvider),
              _buildLendTakenTab(dataProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLendGivenTab(DataProvider dataProvider) {
    final people = dataProvider.getLendGivenPeople();
    final totalOutstanding = dataProvider.getTotalLendGiven();
    final activePeople = people.where((p) => 
        dataProvider.getOutstandingLendGiven(p) > 0).toList();

    return RefreshIndicator(
      onRefresh: () => dataProvider.loadTransactions(),
      child: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          _buildSummaryCard(
            title: 'Total to Receive',
            amount: totalOutstanding,
            icon: Icons.arrow_downward_rounded,
            color: AppColors.success,
            count: activePeople.length,
          ),
          const SizedBox(height: 24),
          if (activePeople.isEmpty)
            _buildEmptyState(
              'No active lends',
              'Money you lent to others will appear here',
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Active Lends',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...activePeople.map((person) {
              final outstanding = dataProvider.getOutstandingLendGiven(person);
              return _buildPersonCard(
                personName: person,
                amount: outstanding,
                type: 'lend_given',
                dataProvider: dataProvider,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildLendTakenTab(DataProvider dataProvider) {
    final people = dataProvider.getLendTakenPeople();
    final totalOutstanding = dataProvider.getTotalLendTaken();
    final activePeople = people.where((p) => 
        dataProvider.getOutstandingLendTaken(p) > 0).toList();

    return RefreshIndicator(
      onRefresh: () => dataProvider.loadTransactions(),
      child: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          _buildSummaryCard(
            title: 'Total to Pay',
            amount: totalOutstanding,
            icon: Icons.arrow_upward_rounded,
            color: AppColors.error,
            count: activePeople.length,
          ),
          const SizedBox(height: 24),
          if (activePeople.isEmpty)
            _buildEmptyState(
              'No active borrows',
              'Money you borrowed from others will appear here',
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Active Borrows',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...activePeople.map((person) {
              final outstanding = dataProvider.getOutstandingLendTaken(person);
              return _buildPersonCard(
                personName: person,
                amount: outstanding,
                type: 'lend_taken',
                dataProvider: dataProvider,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
    required int count,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha:0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            FormatUtils.formatCurrency(amount),
            style: TextStyle(
              color: color,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBackground : AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : AppColors.border),
            ),
            child: Text(
              '$count ${count == 1 ? 'person' : 'people'}',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard({
    required String personName,
    required double amount,
    required String type,
    required DataProvider dataProvider,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: InkWell(
        onTap: () => _showPersonDetails(personName, type, dataProvider),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: type == 'lend_given' 
                      ? AppColors.success.withValues(alpha:0.1)
                      : AppColors.error.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    personName[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: type == 'lend_given' ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      personName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type == 'lend_given' ? 'To receive' : 'To pay',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.formatCurrency(amount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: type == 'lend_given' ? AppColors.success : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payments_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.3),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showPersonDetails(String personName, String type, DataProvider dataProvider) {
    final transactions = dataProvider.transactions
        .where((t) => 
          t.personName == personName && 
          (type == 'lend_given' 
              ? (t.type == 'lend_given' || t.type == 'lend_returned_expense')
              : (t.type == 'lend_taken' || t.type == 'lend_returned_income')))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalGiven = transactions
        .where((t) => t.type == 'lend_given' || t.type == 'lend_taken')
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final totalReturned = transactions
        .where((t) => t.type == 'lend_returned_expense' || t.type == 'lend_returned_income')
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final outstanding = totalGiven - totalReturned;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: type == 'lend_given' 
                        ? AppColors.income.withValues(alpha:0.15)
                        : AppColors.expense.withValues(alpha:0.15),
                    child: Text(
                      personName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: type == 'lend_given' ? AppColors.income : AppColors.expense,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          type == 'lend_given' ? 'Lend Given' : 'Lend Taken',
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Total Given',
                      FormatUtils.formatCurrency(totalGiven),
                      AppColors.textSecondary,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: AppColors.divider,
                    ),
                    _buildStatColumn(
                      'Returned',
                      FormatUtils.formatCurrency(totalReturned),
                      AppColors.success,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: AppColors.divider,
                    ),
                    _buildStatColumn(
                      'Outstanding',
                      FormatUtils.formatCurrency(outstanding),
                      type == 'lend_given' ? AppColors.income : AppColors.expense,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Transaction History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: transactions.isEmpty
                    ? Center(
                        child: Text(
                          'No transactions yet',
                          style: TextStyle(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          final isGiven = transaction.type == 'lend_given' || 
                                        transaction.type == 'lend_taken';
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isGiven
                                    ? (type == 'lend_given' ? AppColors.expense : AppColors.income)
                                        .withValues(alpha:0.15)
                                    : (type == 'lend_given' ? AppColors.income : AppColors.expense)
                                        .withValues(alpha:0.15),
                                child: Icon(
                                  isGiven 
                                      ? (type == 'lend_given' ? Icons.arrow_upward : Icons.arrow_downward)
                                      : (type == 'lend_given' ? Icons.arrow_downward : Icons.arrow_upward),
                                  color: isGiven
                                      ? (type == 'lend_given' ? AppColors.expense : AppColors.income)
                                      : (type == 'lend_given' ? AppColors.income : AppColors.expense),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                isGiven 
                                    ? (type == 'lend_given' ? 'Lent' : 'Borrowed')
                                    : (type == 'lend_given' ? 'Received back' : 'Returned'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    FormatUtils.formatDate(transaction.date),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (transaction.remarks != null)
                                    Text(
                                      transaction.remarks!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: Text(
                                FormatUtils.formatCurrency(transaction.amount),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isGiven
                                      ? (type == 'lend_given' ? AppColors.expense : AppColors.income)
                                      : (type == 'lend_given' ? AppColors.income : AppColors.expense),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
