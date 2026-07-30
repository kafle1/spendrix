# Spendrix 💰

**Smart Money Management Made Simple**

Spendrix is a modern, intuitive expense tracking application built with Flutter. Track your income, expenses, and manage your finances with ease across all your devices.

[![Flutter](https://img.shields.io/badge/Flutter-3.8.1+-blue.svg)](https://flutter.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.3.0-green.svg)](https://github.com/kafle1/spendrix/releases)

## ✨ Features

### 💳 Financial Management
- **Transaction Tracking** - Record income and expenses with categories
- **Multiple Accounts** - Manage multiple bank accounts, wallets, and payment methods
- **Spending Limits** - Set daily, weekly, or monthly budget limits per category
- **Lend & Borrow** - Track money lent to or borrowed from others
- **Google Sign-In** - Secure authentication via Firebase Auth
- **Data Export** - Export all app data to JSON for backup and portability, or generate PDF transaction reports

### 📊 Analytics & Reports
- **Visual Analytics** - Beautiful charts and graphs for expense breakdown
- **Custom Reports** - Generate reports for any time period
- **Category Insights** - See spending patterns by category
- **Budget Progress** - Track spending limits with visual indicators

### 🎨 User Experience
- **Dark Mode** - Full support for light and dark themes
- **Modern UI** - Clean, intuitive interface with smooth animations
- **Customizable** - Toggle features like lend/borrow tracking
- **Responsive** - Works seamlessly on phones and tablets

## 📱 Screenshots

*Screenshots coming soon*

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.8.1 or higher
- Dart SDK 3.8.1 or higher
- Android Studio / Xcode (for mobile development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/kafle1/spendrix.git
   cd spendrix
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## 🏗️ Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── account.dart
│   ├── category.dart
│   ├── transaction.dart
│   └── spending_limit.dart
├── screens/                  # UI screens
│   ├── home_screen.dart
│   ├── add_transaction_screen.dart
│   ├── reports_screen.dart
│   ├── lend_borrow_screen.dart
│   └── settings_screen.dart
├── providers/                # State management
│   └── data_provider.dart
├── database/                 # SQLite database
│   └── database_helper.dart
├── services/                 # Auth, export, analytics, settings
│   ├── auth_service.dart
│   ├── data_export_service.dart
│   ├── firebase_analytics_service.dart
│   └── settings_service.dart
└── utils/                    # Utilities
    ├── app_theme.dart
    └── format_utils.dart
```

## 🛠️ Built With

- **[Flutter](https://flutter.dev/)** - UI framework
- **[Provider](https://pub.dev/packages/provider)** - State management
- **[SQLite](https://pub.dev/packages/sqflite)** - Local database
- **[FL Chart](https://pub.dev/packages/fl_chart)** - Beautiful charts
- **[Google Fonts](https://pub.dev/packages/google_fonts)** - Typography
- **[Firebase](https://firebase.google.com/)** - Authentication, analytics, and crash reporting
- **[pdf / printing](https://pub.dev/packages/pdf)** - PDF transaction report generation

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) for details on how to submit pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to the Flutter team for the amazing framework
- Icons from [Material Design Icons](https://fonts.google.com/icons)
- Inspiration from various personal finance apps

## 📮 Contact

**Niraj Kafle**
- GitHub: [@kafle1](https://github.com/kafle1)

## 🗺️ Roadmap

- [ ] CSV/Excel export (JSON export already available)
- [ ] Cloud sync and backup
- [ ] Receipt scanning with OCR
- [ ] Multi-currency support
- [ ] Recurring transactions
- [ ] Financial goal tracking
- [ ] Bank integration

---

**Made with ❤️ using Flutter**
