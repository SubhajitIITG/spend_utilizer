// Spending / income categories and keyword-based auto-categorisation.

class Category {
  final String name;
  final String emoji;
  const Category(this.name, this.emoji);
}

const debitCategories = <Category>[
  Category('Groceries', '🛒'),
  Category('Food & Dining', '🍔'),
  Category('Utilities & Bills', '💡'),
  Category('Mobile & Internet', '📱'),
  Category('Rent', '🏠'),
  Category('Transport', '🚕'),
  Category('Fuel', '⛽'),
  Category('Shopping', '🛍️'),
  Category('Entertainment', '🎬'),
  Category('Health', '💊'),
  Category('Education', '📚'),
  Category('Travel', '✈️'),
  Category('EMI & Loans', '🏦'),
  Category('Investments', '📈'),
  Category('Insurance', '🛡️'),
  Category('Personal Care', '💇'),
  Category('Gifts & Donations', '🎁'),
  Category(friendsCategory, '👥'),
  Category(payeesCategory, '💸'),
  Category('Others', '📦'),
];

const creditCategories = <Category>[
  Category('Salary', '💼'),
  Category('Refund', '↩️'),
  Category('Cashback & Rewards', '🎉'),
  Category('Interest', '🏦'),
  Category('Investment Returns', '📈'),
  Category('Gift Received', '🎁'),
  Category('Business Income', '🧾'),
  Category('Transfer', '🔁'),
  Category('Others', '📦'),
];

/// Regular payments to a person (not a shop), e.g. splitting chai daily.
const friendsCategory = 'Friends & Family';

/// Money sent to people by bank transfer / UPI (not to shops).
const payeesCategory = 'Payees';

/// Categories that mean "we couldn't tell": payments in these are worth
/// asking the user about.
const unclearCategories = {'Others', 'Transfer', payeesCategory};

const lendCategory = 'Lent';
const borrowCategory = 'Borrowed';

String emojiFor(String category) {
  for (final c in [...debitCategories, ...creditCategories]) {
    if (c.name == category) return c.emoji;
  }
  if (category == lendCategory) return '🤝';
  if (category == borrowCategory) return '🙏';
  return '📦';
}

/// Keyword → category rules for money going out. Matched against the
/// merchant name and the full message text (lower-cased).
const _debitRules = <String, List<String>>{
  'Groceries': [
    'bigbasket',
    'blinkit',
    'zepto',
    'grofers',
    'dmart',
    'jiomart',
    'reliance fresh',
    'more retail',
    'instamart',
    'grocery',
    'supermarket',
    'kirana',
    'spencer',
    'nature basket',
    'milkbasket',
    'country delight',
  ],
  'Food & Dining': [
    'swiggy',
    'zomato',
    'restaurant',
    'cafe',
    'dominos',
    'domino',
    'pizza',
    'mcdonald',
    'kfc',
    'starbucks',
    'burger',
    'eatsure',
    'food',
    'dining',
    'hotel',
    'biryani',
    'bakery',
    'chai',
  ],
  'Mobile & Internet': [
    'jio',
    'airtel',
    'vodafone',
    'vi ',
    'bsnl',
    'recharge',
    'broadband',
    'act fibernet',
    'hathway',
    'prepaid',
    'postpaid',
  ],
  'Utilities & Bills': [
    'electricity',
    'bescom',
    'tneb',
    'msedcl',
    'tata power',
    'adani',
    'water bill',
    'gas',
    'indane',
    'hp gas',
    'bharat gas',
    'bill pay',
    'billdesk',
    'dth',
    'tata play',
    'utility',
  ],
  'Rent': ['rent', 'nobroker', 'housing', 'landlord', 'pg '],
  'Fuel': [
    'petrol',
    'fuel',
    'diesel',
    'indian oil',
    'iocl',
    'hpcl',
    'bpcl',
    'bharat petroleum',
    'shell',
    'nayara',
  ],
  'Transport': [
    'uber',
    'ola',
    'rapido',
    'metro',
    'irctc',
    'redbus',
    'fastag',
    'parking',
    'toll',
    'namma yatri',
    'abhibus',
    'auto rickshaw',
  ],
  'Travel': [
    'makemytrip',
    'goibibo',
    'cleartrip',
    'yatra',
    'indigo',
    'airindia',
    'air india',
    'vistara',
    'spicejet',
    'akasa',
    'oyo',
    'airbnb',
    'booking.com',
    'agoda',
    'ixigo',
  ],
  'Shopping': [
    'amazon',
    'flipkart',
    'myntra',
    'ajio',
    'meesho',
    'nykaa',
    'tatacliq',
    'croma',
    'reliance digital',
    'decathlon',
    'ikea',
    'lenskart',
    'mall',
    'store',
    'mart',
    'shop',
  ],
  'Entertainment': [
    'netflix',
    'spotify',
    'hotstar',
    'prime video',
    'youtube',
    'bookmyshow',
    'pvr',
    'inox',
    'sonyliv',
    'zee5',
    'gaming',
    'steam',
    'playstation',
  ],
  'Health': [
    'pharmacy',
    'apollo',
    'medplus',
    'pharmeasy',
    '1mg',
    'netmeds',
    'hospital',
    'clinic',
    'diagnostic',
    'lab',
    'doctor',
    'medical',
    'practo',
    'cult.fit',
    'cultfit',
    'gym',
  ],
  'Education': [
    'school',
    'college',
    'university',
    'tuition',
    'coursera',
    'udemy',
    'byju',
    'unacademy',
    'fees',
    'exam',
    'books',
  ],
  'EMI & Loans': ['emi', 'loan', 'bajaj finserv', 'nach', 'ecs'],
  'Investments': [
    'zerodha',
    'groww',
    'upstox',
    'mutual fund',
    'sip',
    'kuvera',
    'coin by',
    'nps',
    'ppf',
    'smallcase',
    'angel one',
    'indmoney',
  ],
  'Insurance': ['insurance', 'lic', 'policybazaar', 'premium', 'acko'],
  'Personal Care': ['salon', 'spa', 'urban company', 'urbanclap', 'parlour'],
  'Gifts & Donations': ['donation', 'charity', 'temple', 'gift', 'ketto'],
};

const _creditRules = <String, List<String>>{
  'Refund': ['refund', 'reversal', 'reversed', 'chargeback'],
  'Cashback & Rewards': ['cashback', 'cash back', 'reward', 'scratch card'],
  'Salary': ['salary', 'sal ', 'payroll', 'neft-sal', 'stipend'],
  'Interest': ['interest', 'int.pd', 'int pd', 'int.cr'],
  'Investment Returns': ['dividend', 'redemption', 'maturity'],
};

final _patternCache = <String, RegExp>{};

/// Keywords must start at a word boundary, so "lab" matches "labs" but not
/// "available", and "lic" does not match "public".
bool _hasKeyword(String haystack, String kw) {
  final re = _patternCache.putIfAbsent(
    kw,
    () => RegExp('(?<![a-z0-9])${RegExp.escape(kw)}'),
  );
  return re.hasMatch(haystack);
}

String _match(Map<String, List<String>> rules, String haystack) {
  for (final entry in rules.entries) {
    for (final kw in entry.value) {
      if (_hasKeyword(haystack, kw)) return entry.key;
    }
  }
  return '';
}

/// Guesses a category from the merchant and the full message.
/// Merchant is checked first so "Amazon refund" style messages still work.
String guessCategory({
  required bool isCredit,
  required String merchant,
  required String message,
}) {
  final m = ' ${merchant.toLowerCase()} ';
  final msg = ' ${message.toLowerCase()} ';
  if (isCredit) {
    final byMsg = _match(_creditRules, msg);
    if (byMsg.isNotEmpty) return byMsg;
    return 'Transfer';
  }
  final byMerchant = _match(_debitRules, m);
  if (byMerchant.isNotEmpty) return byMerchant;
  final byMsg = _match(_debitRules, msg);
  if (byMsg.isNotEmpty) return byMsg;
  return 'Others';
}
