// Spending / income categories and keyword-based auto-categorisation.

class Category {
  final String name;
  final String emoji;
  const Category(this.name, this.emoji);
}

/// Every kind of investment, in the order the Dashboard and the Invest
/// button list them. Money put into these is "Invested", not "Spent".
const investmentTypes = <Category>[
  Category(sipCategory, '📈'),
  Category(stocksCategory, '📊'),
  Category(fdCategory, '🏛️'),
  Category(rdCategory, '📅'),
  Category(ppfCategory, '🐖'),
  Category(epfCategory, '👔'),
  Category(npsCategory, '👴'),
  Category(goldCategory, '🪙'),
  Category(bondsCategory, '📜'),
  Category(postOfficeCategory, '📮'),
  Category(sukanyaCategory, '👧'),
  Category(realEstateCategory, '🏘️'),
  Category(cryptoCategory, '₿'),
  Category(ulipCategory, '🛡️'),
  Category(p2pCategory, '🤲'),
  Category(otherInvestCategory, '💹'),
];

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
  ...investmentTypes,
  Category('Insurance', '🛡️'),
  Category('Personal Care', '💇'),
  Category('Gifts & Donations', '🎁'),
  Category(friendsCategory, '👥'),
  Category(payeesCategory, '💸'),
  Category(cardBillCategory, '💳'),
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

/// Monthly SIPs / mutual fund purchases. Saved, not spent: shown as
/// "Invested" and left out of spending totals (with other investments).
const sipCategory = 'SIP & Mutual Funds';
const fdCategory = 'Fixed Deposit';
const rdCategory = 'Recurring Deposit';
const stocksCategory = 'Stocks';
const bondsCategory = 'Bonds';

const ppfCategory = 'PPF';
const epfCategory = 'EPF / VPF';
const npsCategory = 'NPS';
const goldCategory = 'Gold & Silver';
const postOfficeCategory = 'Post Office Schemes';
const sukanyaCategory = 'Sukanya Samriddhi';
const realEstateCategory = 'Real Estate';
const cryptoCategory = 'Crypto';
const ulipCategory = 'ULIP & Savings Plans';
const p2pCategory = 'P2P Lending';

/// Anything else (kept as "Investments" for existing data).
const otherInvestCategory = 'Investments';

/// Investment types, in the order the Dashboard lists them.
final investmentCategoryOrder = [for (final c in investmentTypes) c.name];
final investmentCategories = investmentCategoryOrder.toSet();

/// How an investment type is shown in lists ("Other investments").
String investmentLabel(String category) =>
    category == otherInvestCategory ? 'Other investments' : category;

/// Debit categories that are real spending (the Debit flow offers these;
/// investments have their own Invest button).
final spendingCategories = debitCategories
    .where((c) => !investmentCategories.contains(c.name))
    .toList();

/// Paying a credit-card bill. Not new spending (the purchases were already
/// counted on the card), so it is left out of spending totals.
const cardBillCategory = 'Credit Card Bill';

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
  // First: "Bill Payment of … Credit Card" must not land in Utilities.
  cardBillCategory: [
    'credit card bill',
    'card bill payment',
    'bill payment of',
    'deposited to card',
    'ccbillpay',
    'cred club',
    'creditcard bill',
  ],
  // SIPs often arrive as auto-debits ("ACH D- BSE LIMITED", "NACH …
  // ICCL"): match them before EMI's generic 'nach'.
  sipCategory: [
    'sip',
    'mutual fund',
    'mutualfund',
    'mf sip',
    'bse limited',
    'bse ltd',
    'bsestarmf',
    'bse star',
    'iccl',
    'indian clearing',
    'cams',
    'kfintech',
    'kfin',
    'mf utilit',
    'groww',
    'kuvera',
    'coin by zerodha',
    'paytm money',
    'et money',
    'etmoney',
    'scripbox',
    'fundsindia',
    'sbi mf',
    'hdfc mf',
    'icici pru',
    'axis mf',
    'nippon india mf',
    'nippon',
    'mirae',
    'ppfas',
    'parag parikh',
    'kotak mf',
    'uti mf',
    'quant mf',
    'aditya birla sun life',
    'absl mf',
    'dsp mf',
    'tata mf',
    'franklin templeton',
    'motilal oswal mf',
    'edelweiss mf',
    'canara robeco',
    'sundaram mf',
    'invesco',
    'hsbc mf',
    'bandhan mf',
  ],
  goldCategory: [
    'digital gold',
    'safegold',
    'mmtc-pamp',
    'augmont',
    'jar app',
    'sgb',
    'sovereign gold',
    'gold etf',
    'goldbees',
    'gold fund',
    'silver etf',
  ],
  bondsCategory: [
    'bond',
    'rbi retail direct',
    'rbi bonds',
    'ncd',
    'debenture',
    'wint wealth',
    'grip invest',
    'goldenpi',
    'indiabonds',
    'tbill',
    't-bill',
    'treasury bill',
    'g-sec',
    'gsec',
  ],
  fdCategory: [
    'fixed deposit',
    'fd booked',
    'fd booking',
    'fd opened',
    'fd opening',
    'fd created',
    'fd a/c',
    'fd ac',
    'fd account',
    'fd no',
    'new fd',
    'term deposit',
    'tdr',
    'stable money',
    'flexi deposit',
  ],
  rdCategory: [
    'recurring deposit',
    'rd instal',
    'rd a/c',
    'rd ac',
    'rd account',
    'rd no',
    'new rd',
  ],
  stocksCategory: [
    'zerodha',
    'upstox',
    'angel one',
    'angel broking',
    'icici direct',
    'icicidirect',
    'icici securities',
    'hdfc securities',
    'kotak securities',
    'sharekhan',
    '5paisa',
    'motilal oswal fin',
    'axis direct',
    'sbicap securities',
    'paytm money stocks',
    'groww stocks',
    'dhan.co',
    'nsccl',
    'nse clearing',
    'shares',
    'stock',
    'equity',
    'ipo',
    'smallcase',
    'indmoney',
  ],
  ppfCategory: ['ppf', 'public provident'],
  sukanyaCategory: ['sukanya', 'ssy a/c', 'ssy account'],
  epfCategory: ['epfo', 'epf ', 'vpf', 'employees provident', 'provident fund'],
  npsCategory: ['nps', 'national pension', 'pran ', 'protean cra', 'kfin cra'],
  postOfficeCategory: [
    'post office',
    'india post',
    'ippb',
    'kisan vikas',
    'kvp',
    'national savings certificate',
    'nsc ',
    'scss',
    'senior citizen savings',
    'pomis',
    'monthly income scheme',
  ],
  cryptoCategory: [
    'wazirx',
    'coindcx',
    'coinswitch',
    'zebpay',
    'mudrex',
    'giottus',
    'bitbns',
    'binance',
    'bitcoin',
    'crypto',
  ],
  realEstateCategory: ['strata', 'hbits', 'property booking', 'reit '],
  ulipCategory: ['ulip'],
  p2pCategory: [
    'lendenclub',
    'faircent',
    'liquiloans',
    'lendbox',
    '12% club',
    'p2p',
  ],
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
  'Insurance': ['insurance', 'lic', 'policybazaar', 'premium', 'acko'],
  'Personal Care': ['salon', 'spa', 'urban company', 'urbanclap', 'parlour'],
  'Gifts & Donations': ['donation', 'charity', 'temple', 'gift', 'ketto'],
};

const _creditRules = <String, List<String>>{
  'Refund': ['refund', 'reversal', 'reversed', 'chargeback'],
  'Cashback & Rewards': ['cashback', 'cash back', 'reward', 'scratch card'],
  'Salary': ['salary', 'sal ', 'payroll', 'neft-sal', 'stipend'],
  'Interest': ['interest', 'int.pd', 'int pd', 'int.cr'],
  'Investment Returns': [
    'dividend',
    'redemption',
    'maturity',
    'matured',
    'fd closure',
    'fd closed',
    'premature',
    'rd closure',
    'interest on fd',
  ],
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
