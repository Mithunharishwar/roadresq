/// RoadResQ Wallet & Loyalty — Wallet Model (novel module).
///
/// In-app secure wallet with a balance, transaction ledger, cashback tiers
/// on completed rescues, and referral rewards.
class WalletModel {
  final String userId;
  final double balance;
  final double lifetimeCashback;
  final double referralBalance;
  final String memberTier; // bronze, silver, gold, platinum
  final int rescueCount;
  final List<WalletTransaction> transactions;
  final List<CashbackRule> cashbackRules;

  WalletModel({
    this.userId = '',
    this.balance = 0,
    this.lifetimeCashback = 0,
    this.referralBalance = 0,
    this.memberTier = 'bronze',
    this.rescueCount = 0,
    this.transactions = const [],
    this.cashbackRules = const [],
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        userId: json['userId']?.toString() ?? '',
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        lifetimeCashback: (json['lifetimeCashback'] as num?)?.toDouble() ?? 0,
        referralBalance: (json['referralBalance'] as num?)?.toDouble() ?? 0,
        memberTier: json['memberTier']?.toString() ?? 'bronze',
        rescueCount: (json['rescueCount'] as num?)?.toInt() ?? 0,
        transactions: (json['transactions'] as List?)
                ?.map((e) =>
                    WalletTransaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        cashbackRules: (json['cashbackRules'] as List?)
                ?.map((e) => CashbackRule.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// A single wallet ledger entry.
class WalletTransaction {
  final String txnId;
  final String type; // credit, debit, cashback, referral, refund
  final double amount;
  final String description;
  final DateTime createdAt;

  WalletTransaction({
    this.txnId = '',
    this.type = 'credit',
    this.amount = 0,
    this.description = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        txnId: json['txnId']?.toString() ?? '',
        type: json['type']?.toString() ?? 'credit',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        description: json['description']?.toString() ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}

/// A configurable cashback rule.
class CashbackRule {
  final String serviceType;
  final double percent;
  final String description;

  CashbackRule({
    this.serviceType = 'general',
    this.percent = 0,
    this.description = '',
  });

  factory CashbackRule.fromJson(Map<String, dynamic> json) => CashbackRule(
        serviceType: json['serviceType']?.toString() ?? 'general',
        percent: (json['percent'] as num?)?.toDouble() ?? 0,
        description: json['description']?.toString() ?? '',
      );
}
