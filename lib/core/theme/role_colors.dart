// FILE: lib/core/theme/role_colors.dart
/// Role palette — one source of truth for the three app roles.
///
/// The brief fixes the brand colours: User red, Mechanic blue, Assistant green.
/// They were previously scattered as literals (and two of the exact hexes were
/// missing entirely), so a screen could not look up "the mechanic colour"
/// without hardcoding it again.
library;

import 'package:material_ui/material_ui.dart';

class RoleColors {
  RoleColors._();

  /// User — rescue requester. #D32F2F
  static const Color user = Color(0xFFD32F2F);

  /// Mechanic — lead responder. #1976D2
  static const Color mechanic = Color(0xFF1976D2);

  /// Assistant — crew partner. #388E3C
  static const Color assistant = Color(0xFF388E3C);

  /// Garage — partner workshop (existing role, kept distinct from the three
  /// primary roles).
  static const Color garage = Color(0xFFF57C00);

  /// Neutral surface tint used by empty/loading states.
  static const Color neutral = Color(0xFF6B7280);

  /// Colour for a role string as used by login and session storage.
  static Color forRole(String? role) {
    switch ((role ?? '').toLowerCase()) {
      case 'user':
        return user;
      case 'mechanic':
        return mechanic;
      case 'assistant':
        return assistant;
      case 'garage':
        return garage;
      case 'admin':
        return const Color(0xFF37474F);
      default:
        return neutral;
    }
  }

  /// Human label for a role string.
  static String labelForRole(String? role) {
    switch ((role ?? '').toLowerCase()) {
      case 'user':
        return 'User';
      case 'mechanic':
        return 'Mechanic';
      case 'assistant':
        return 'Assistant';
      case 'garage':
        return 'Garage';
      case 'admin':
        return 'Admin';
      default:
        return 'Guest';
    }
  }

  /// Soft background for cards and chips in the role colour.
  static Color tint(Color base, {double opacity = 0.10}) =>
      base.withValues(alpha: opacity);
}
