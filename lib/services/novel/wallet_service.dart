/// RoadResQ Wallet & Loyalty — Wallet Service (novel module).
///
/// In-app wallet with a balance, transaction ledger, cashback + referral
/// rewards, and member tiers unlocked by rescue count.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/novel/wallet_model.dart';

class WalletService {
  WalletService._internal();
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ─── Get or create the wallet for a user ───
  Future<WalletModel> getWallet(String userId) async {
    try {
      final doc = await _firestore.collection('wallets').doc(userId).get();
      if (doc.exists) {
        return WalletModel.fromJson(
            Map<String, dynamic>.from(doc.data() as Map));
      }
      // Create a fresh wallet.
      final wallet = WalletModel(
        userId: userId,
        balance: 0,
        memberTier: 'bronze',
        rescueCount: 0,
        cashbackRules: _defaultCashbackRules(),
      );
      await _firestore.collection('wallets').doc(userId).set({
        'userId': userId,
        'balance': 0,
        'lifetimeCashback': 0,
        'referralBalance': 0,
        'memberTier': 'bronze',
        'rescueCount': 0,
        'transactions': [],
        'cashbackRules': _defaultCashbackRules()
            .map((r) => {
                  'serviceType': r.serviceType,
                  'percent': r.percent,
                  'description': r.description,
                })
            .toList(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return wallet;
    } catch (e) {
      debugPrint('WalletService.getWallet error: $e');
      return WalletModel(userId: userId);
    }
  }

  List<CashbackRule> _defaultCashbackRules() => [
        CashbackRule(
            serviceType: 'flat_tyre', percent: 5, description: 'Flat Tyre'),
        CashbackRule(
            serviceType: 'battery', percent: 6, description: 'Battery Jump'),
        CashbackRule(
            serviceType: 'fuel', percent: 4, description: 'Fuel Delivery'),
        CashbackRule(serviceType: 'towing', percent: 3, description: 'Towing'),
        CashbackRule(
            serviceType: 'lockout', percent: 5, description: 'Lockout Help'),
      ];

  /// ─── Credit cashback after a completed rescue ───
  Future<Map<String, dynamic>> creditCashback({
    required String userId,
    required double amount,
    required String serviceType,
  }) async {
    try {
      final wallet = await getWallet(userId);
      final rule = wallet.cashbackRules.firstWhere(
          (r) => r.serviceType == serviceType,
          orElse: () => CashbackRule(percent: 4));
      final cashback = amount * rule.percent / 100;

      final txn = WalletTransaction(
        txnId: _newId('cashback'),
        type: 'cashback',
        amount: cashback,
        description: 'Cashback on $serviceType rescue',
      );

      final newBalance = wallet.balance + cashback;
      final newLifetime = wallet.lifetimeCashback + cashback;
      final newRescueCount = wallet.rescueCount + 1;
      final newTier = _tierFor(newRescueCount);

      await _firestore.collection('wallets').doc(userId).update({
        'balance': newBalance,
        'lifetimeCashback': newLifetime,
        'rescueCount': newRescueCount,
        'memberTier': newTier,
        'transactions': FieldValue.arrayUnion([
          {
            'txnId': txn.txnId,
            'type': txn.type,
            'amount': txn.amount,
            'description': txn.description,
            'createdAt': txn.createdAt.toIso8601String(),
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'cashback': cashback,
        'newBalance': newBalance,
        'tier': newTier,
      };
    } catch (e) {
      debugPrint('WalletService.creditCashback error: $e');
      return {'success': false, 'cashback': 0, 'newBalance': 0, 'tier': ''};
    }
  }

  /// ─── Credit referral reward to the referrer ───
  Future<bool> creditReferral({
    required String referrerId,
    required double rewardAmount,
    String? referredName,
  }) async {
    try {
      final wallet = await getWallet(referrerId);
      await _firestore.collection('wallets').doc(referrerId).update({
        'referralBalance': wallet.referralBalance + rewardAmount,
        'balance': wallet.balance + rewardAmount,
        'transactions': FieldValue.arrayUnion([
          {
            'txnId': _newId('referral'),
            'type': 'referral',
            'amount': rewardAmount,
            'description':
                'Referral reward${referredName != null ? ' — joined $referredName' : ''}',
            'createdAt': DateTime.now().toIso8601String(),
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('WalletService.creditReferral error: $e');
      return false;
    }
  }

  /// ─── Deduct from wallet (used to offset payment) ───
  Future<Map<String, dynamic>> debit({
    required String userId,
    required double amount,
    required String description,
  }) async {
    try {
      final wallet = await getWallet(userId);
      if (wallet.balance < amount) {
        return {'success': false, 'message': 'Insufficient balance'};
      }
      final newBalance = wallet.balance - amount;
      await _firestore.collection('wallets').doc(userId).update({
        'balance': newBalance,
        'transactions': FieldValue.arrayUnion([
          {
            'txnId': _newId('debit'),
            'type': 'debit',
            'amount': amount,
            'description': description,
            'createdAt': DateTime.now().toIso8601String(),
          }
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'newBalance': newBalance};
    } catch (e) {
      debugPrint('WalletService.debit error: $e');
      return {'success': false, 'message': 'Debit failed'};
    }
  }

  String _tierFor(int rescueCount) {
    if (rescueCount >= 20) return 'platinum';
    if (rescueCount >= 10) return 'gold';
    if (rescueCount >= 5) return 'silver';
    return 'bronze';
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().millisecondsSinceEpoch}';
}
