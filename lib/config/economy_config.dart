// lib/config/economy_config.dart
//
// Central knobs for Servana's in-app economy.

class EconomyConfig {
  static const int minApplyCoins = 400;          // minimum coins to apply
  static const int graceMinutesForTopUp = 15;    // minutes to top up after approval if coins insufficient
  static const int platformFeePct = 10;          // % of offer price charged as commission (coins)
}
