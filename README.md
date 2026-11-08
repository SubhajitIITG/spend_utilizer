# Spend Utilizer

A **chat-based expense tracker** for Android, Windows and Linux. Copy a bank or
UPI transaction SMS, paste it into the chat, and the app works out the details
for you:

- **How much** was spent or received
- **Debit or credit** (refunds are detected as credits)
- **Which bank**, and whether it was a **savings account, credit card or debit card**
- The account or card's **last 4 digits**. Three credit cards from the same
  bank become three separate cards, each with its own name.
- **Where** the money went (merchant / UPI ID / person) and an auto **category**
  (Groceries, Food, Utilities, Shopping and so on)
- UPI reference number and date. The same SMS pasted twice is ignored.

## Features

| Area | What it does |
|---|---|
| 💬 **Chat** | Paste one SMS, or many at once separated by blank lines. Quick actions: **Paste SMS, Debit, Credit, Lend, Borrow, Reminder** |
| ➖ **Debit** | Asks amount, then category (Groceries, Food & Dining, Utilities…), then account, then note |
| ➕ **Credit** | Asks amount, then category (Salary, **Refund**, Cashback…), then account, then note |
| 🤝 **Lend / 🙏 Borrow** | Asks the person's name, then amount, then account, then due date (creates a reminder) |
| ⏰ **Reminder** | Anything you want to be reminded about, with an optional amount |
| 📊 **Dashboard** | Monthly spent / received / net, category pie chart, number of banks / cards / accounts, spend per card, who owes whom, reminders |
| 🧾 **History** | Search and filter all entries. Tap one to edit or delete it |
| 🏦 **Accounts** | Rename a bank, give cards nicknames (e.g. "HDFC Millennia"), change the type, add accounts manually |
| 📥 **Excel export** | Download icon. Saves a `.xlsx` with sheets for Transactions, Monthly Summary, Category Summary, Accounts, Lend & Borrow and Reminders |

All data stays **on your device** in a local file. Nothing is uploaded.

## Getting the app

Every push to `main` (and every pull request) runs **GitHub Actions**, which
tests the app and builds it for each platform. To download:

1. Open the repo's **Actions** tab, then the latest **Build apps** run.
2. Scroll to **Artifacts** and download one of these:
   - `spend-utilizer-android-apk`: install the `.apk` on your phone (allow
     "install from unknown sources").
   - `spend-utilizer-windows`: unzip and run `spend_utilizer.exe`.
   - `spend-utilizer-linux`: unzip and run `./spend_utilizer`. Saving Excel
     files needs `zenity` (`sudo apt install zenity`).

## Developing

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable).

```bash
flutter pub get
flutter test          # parser, chat flows, Excel export, UI smoke test
flutter run -d linux  # or: -d windows, or a connected Android phone
```

### Project layout

```
lib/
  main.dart                  app shell + navigation (bottom bar on phones, side rail on desktop)
  models/models.dart         Account, Txn, Reminder, ChatMessage
  data/store.dart            state + local JSON storage + statistics
  services/sms_parser.dart   bank/UPI SMS → structured transaction
  services/categories.dart   category lists + auto-categorisation keywords
  services/chat_engine.dart  chat conversation logic (guided flows)
  services/excel_export.dart .xlsx statement builder
  ui/                        chat, dashboard, history, accounts, editors
test/                        unit + widget tests
```

### Supporting a new bank message format

If an SMS isn't understood (or is read wrongly), add it as a test case in
`test/sms_parser_test.dart` with the expected values, then adjust the rules
in `lib/services/sms_parser.dart` until the tests pass. To improve
auto-categorisation, add merchant keywords in `lib/services/categories.dart`.
