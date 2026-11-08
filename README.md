# Spend Utilizer

A **chat-based expense tracker** for Android, Windows, macOS and Linux. Copy a bank or
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
| 📷 **Payment screenshots** (Android) | Add a screenshot in the chat, or **share a receipt straight from Google Pay, PhonePe, Paytm, BHIM or Photos** (Spend Utilizer appears in the share sheet). It's read on the phone and checked for signs of editing. You can also share a bank SMS from the Messages app |
| 🔎 **Learns your merchants** | If you pay the same UPI ID / stall 3+ times in 30 days in small amounts (≤ ₹2,000) and the app can't tell what it is, it asks once: **a friend**, or which category (Food, Groceries…), plus an optional name like "Raju Tea Stall". Past and future payments are categorised automatically. Changing a payment's category by hand also teaches the app. Review everything under **Accounts → Merchants** |
| 💸 **Payees** | Money sent to people (NEFT/IMPS/bank transfer, UPI to a person) is filed under **Payees**; filter it in History |
| 🏦 **Accounts** | Rename a bank, give cards nicknames (e.g. "HDFC Millennia"), change the type, add accounts manually |
| 📥 **Excel export** | Download icon. Saves a `.xlsx` with sheets for Transactions, Monthly Summary, Category Summary, Accounts, Lend & Borrow and Reminders |
| 🔐 **Login & sync** | Sign in with **email + password** or as a **guest** (phone/SMS login is built in but switched off until an SMS provider is set up: `phoneLoginEnabled` in `lib/config.dart`). Your data then syncs across all your devices. Works offline and catches up when you're back online |

Data is always saved on the device first. Cloud sync is optional and needs a
free Supabase project: see **[SETUP.md](SETUP.md)** (about 10 minutes).
Without it, the app works offline with no login.

## Getting the app

Every push to `main` (and every pull request) runs **GitHub Actions**, which
tests the app and builds it for each platform. To download:

1. Open the repo's **Actions** tab, then the latest **Build apps** run.
2. Scroll to **Artifacts** and download one of these:
   - `spend-utilizer-android-apk`: install the `.apk` on your phone (allow
     "install from unknown sources").
   - `spend-utilizer-windows`: unzip and run `spend_utilizer.exe`.
   - `spend-utilizer-macos`: unzip, then **right-click** "Spend Utilizer" and
     choose **Open** the first time. The app isn't signed with an Apple
     developer certificate yet, so macOS warns about it.
   - `spend-utilizer-linux`: unzip and run `./spend_utilizer`. Saving Excel
     files needs `zenity` (`sudo apt install zenity`).

## Developing

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable).

```bash
flutter pub get
flutter test          # parser, chat flows, sync, Excel export, UI smoke test
flutter run -d linux  # or: -d windows, -d macos, or a connected Android phone
# with login & sync (see SETUP.md):
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
```

### Project layout

```
lib/
  main.dart                  startup, login gate, navigation (bottom bar on phones, side rail on desktop)
  config.dart                Supabase URL / key (via --dart-define)
  models/models.dart         Account, Txn, Reminder, ChatMessage
  data/store.dart            state + local JSON storage + statistics
  services/sms_parser.dart   bank/UPI SMS → structured transaction
  services/categories.dart   category lists + auto-categorisation keywords
  services/chat_engine.dart  chat conversation logic (guided flows)
  services/excel_export.dart .xlsx statement builder
  services/auth_service.dart email / phone / guest login (Supabase Auth)
  services/sync_service.dart upload local changes, download remote ones, newest edit wins
  services/supabase_backend.dart  cloud storage for sync
  ui/                        chat, dashboard, history, accounts, login, account & sync
supabase/schema.sql          database table + row-level security (run once)
test/                        unit + widget tests
```

### Supporting a new bank message format

If an SMS isn't understood (or is read wrongly), add it as a test case in
`test/sms_parser_test.dart` with the expected values, then adjust the rules
in `lib/services/sms_parser.dart` until the tests pass. To improve
auto-categorisation, add merchant keywords in `lib/services/categories.dart`.
