enum AppMode {
  expenseOnly,
  loanOnly,
  both,
}

extension AppModeExtension on AppMode {
  String get displayName {
    switch (this) {
      case AppMode.expenseOnly:
        return 'Expense Tracking';
      case AppMode.loanOnly:
        return 'Loan Tracking';
      case AppMode.both:
        return 'Full Mode';
    }
  }

  String get description {
    switch (this) {
      case AppMode.expenseOnly:
        return 'Track your income and expenses only';
      case AppMode.loanOnly:
        return 'Track money lent and borrowed only';
      case AppMode.both:
        return 'Track both expenses and loans';
    }
  }

  bool get hasExpenseTracking => this == AppMode.expenseOnly || this == AppMode.both;
  bool get hasLoanTracking => this == AppMode.loanOnly || this == AppMode.both;

  static AppMode fromString(String value) {
    switch (value) {
      case 'expenseOnly':
        return AppMode.expenseOnly;
      case 'loanOnly':
        return AppMode.loanOnly;
      case 'both':
        return AppMode.both;
      default:
        return AppMode.both;
    }
  }
}
