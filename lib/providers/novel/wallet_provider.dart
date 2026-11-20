/// RoadResQ Wallet & Loyalty Provider (novel module).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/wallet_model.dart';
import '../../services/novel/wallet_service.dart';

/// ─── State ───
class WalletState {
  final bool isLoading;
  final String? errorMessage;
  final WalletModel? wallet;
  final String? lastActionMessage;

  const WalletState({
    this.isLoading = false,
    this.errorMessage,
    this.wallet,
    this.lastActionMessage,
  });

  WalletState copyWith({
    bool? isLoading,
    String? errorMessage,
    WalletModel? wallet,
    String? lastActionMessage,
  }) {
    return WalletState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      wallet: wallet ?? this.wallet,
      lastActionMessage: lastActionMessage ?? this.lastActionMessage,
    );
  }
}

/// ─── Notifier ───
class WalletNotifier extends StateNotifier<WalletState> {
  final WalletService _service;

  WalletNotifier(this._service) : super(const WalletState());

  /// Load (or create) the wallet for a user.
  Future<void> loadWallet(String userId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final wallet = await _service.getWallet(userId);
    state = state.copyWith(isLoading: false, wallet: wallet);
  }

  /// Credit cashback after a completed rescue.
  Future<void> creditCashback({
    required String userId,
    required double amount,
    required String serviceType,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _service.creditCashback(
      userId: userId,
      amount: amount,
      serviceType: serviceType,
    );
    String message;
    if (result['success'] == true) {
      message =
          'Cashback ₹${(result['cashback'] as num).toStringAsFixed(2)} credited. '
          'New balance ₹${(result['newBalance'] as num).toStringAsFixed(2)}. '
          'Tier: ${result['tier']}';
      final wallet = await _service.getWallet(userId);
      state = state.copyWith(isLoading: false, wallet: wallet);
    } else {
      message = 'Cashback failed';
      state = state.copyWith(isLoading: false, errorMessage: message);
    }
    state = state.copyWith(lastActionMessage: message);
  }

  /// Credit a referral reward.
  Future<void> creditReferral({
    required String referrerId,
    required double rewardAmount,
    String? referredName,
  }) async {
    final ok = await _service.creditReferral(
      referrerId: referrerId,
      rewardAmount: rewardAmount,
      referredName: referredName,
    );
    final wallet = await _service.getWallet(referrerId);
    state = state.copyWith(
      wallet: wallet,
      lastActionMessage: ok
          ? 'Referral reward of ₹$rewardAmount credited.'
          : 'Referral credit failed',
    );
  }

  /// Debit from the wallet (offset a payment).
  Future<bool> debit({
    required String userId,
    required double amount,
    required String description,
  }) async {
    final result = await _service.debit(
      userId: userId,
      amount: amount,
      description: description,
    );
    if (result['success'] == true) {
      final wallet = await _service.getWallet(userId);
      state = state.copyWith(wallet: wallet);
    }
    return result['success'] == true;
  }

  void reset() => state = const WalletState();
}

/// ─── Provider ───
final walletProvider =
    StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier(WalletService());
});
