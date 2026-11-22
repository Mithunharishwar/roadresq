/// RoadResQ Wallet & Loyalty Screen (novel module).
///
/// Shows wallet balance, member tier, transaction ledger, and lets the user
/// credit cashback / referral rewards (demo actions).
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/novel/wallet_model.dart';
import '../../providers/novel/wallet_provider.dart';
import '../../widgets/novel/novel_widgets.dart';

class WalletScreen extends ConsumerStatefulWidget {
  final String userId;

  const WalletScreen({super.key, this.userId = 'user1'});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadWallet(widget.userId);
    });
  }

  Future<void> _creditCashback() async {
    await ref.read(walletProvider.notifier).creditCashback(
          userId: widget.userId,
          amount: 500,
          serviceType: 'flat_tyre',
        );
  }

  Future<void> _creditReferral() async {
    await ref.read(walletProvider.notifier).creditReferral(
          referrerId: widget.userId,
          rewardAmount: 100,
          referredName: 'Priya',
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletProvider);
    final wallet = state.wallet;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NovelHero(
              title: 'RoadResQ Wallet',
              subtitle: 'Cashback, Referrals & Loyalty Rewards',
              icon: Icons.account_balance_wallet,
              colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
            ),
            const SizedBox(height: 20),
            if (wallet == null)
              const NovelEmptyCard(
                message: 'Loading wallet...',
                icon: Icons.account_balance_wallet_outlined,
              )
            else ...[
              // Balance card
              _balanceCard(wallet),

              const SizedBox(height: 16),

              Row(
                children: [
                  NovelStatCard(
                    title: 'Tier',
                    value: _tierLabel(wallet.memberTier),
                    color: _tierColor(wallet.memberTier),
                    icon: Icons.stars,
                  ),
                  const SizedBox(width: 10),
                  NovelStatCard(
                    title: 'Rescues',
                    value: '${wallet.rescueCount}',
                    color: const Color(0xFF0D47A1),
                    icon: Icons.emergency,
                  ),
                  const SizedBox(width: 10),
                  NovelStatCard(
                    title: 'Referral',
                    value: '₹${wallet.referralBalance.toStringAsFixed(0)}',
                    color: const Color(0xFF2E7D32),
                    icon: Icons.group_add,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Reward Actions',
                icon: Icons.redeem,
                color: const Color(0xFFB71C1C),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _creditCashback,
                      icon: const Icon(Icons.wallet_giftcard),
                      label: const Text('Cashback'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _creditReferral,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Referral'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),

              if (state.lastActionMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF2E7D32).withAlpha((0.1 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    state.lastActionMessage!,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Color(0xFF2E7D32), fontSize: 13),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              NovelSectionTitle(
                title: 'Transaction Ledger',
                icon: Icons.receipt_long,
                color: const Color(0xFF0D47A1),
              ),
              const SizedBox(height: 12),
              if (wallet.transactions.isEmpty)
                const NovelEmptyCard(
                  message: 'No transactions yet.',
                  icon: Icons.receipt_long_outlined,
                )
              else
                ...wallet.transactions
                    .toList()
                    .reversed
                    .map((t) => _txnTile(t)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(WalletModel wallet) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB71C1C).withAlpha((0.3 * 255).round()),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available Balance',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '₹${wallet.balance.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Lifetime cashback: ₹${wallet.lifetimeCashback.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _txnTile(WalletTransaction t) {
    final isCredit =
        t.type == 'cashback' || t.type == 'referral' || t.type == 'credit';
    final color = isCredit ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
    final sign = isCredit ? '+' : '-';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(isCredit ? Icons.add_circle : Icons.remove_circle,
              color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.description,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  '${t.createdAt.day}-${t.createdAt.month}-${t.createdAt.year}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
          Text('$sign₹${t.amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: color, fontSize: 14)),
        ],
      ),
    );
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'gold':
        return 'Gold';
      case 'platinum':
        return 'Platinum';
      case 'silver':
        return 'Silver';
      default:
        return 'Bronze';
    }
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'gold':
        return const Color(0xFFFF8F00);
      case 'platinum':
        return const Color(0xFF7B1FA2);
      case 'silver':
        return const Color(0xFF607D8B);
      default:
        return const Color(0xFF8D6E63);
    }
  }
}
