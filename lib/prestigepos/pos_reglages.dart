// lib/prestigepos/pos_reglages.dart
// PrestigePOS — réglages propres à l'application (SharedPreferences de PrestigePOS, distinctes de celles de
// Prestige Mobile : autre applicationId, autre stockage) : assistant terminé, mobile money proposé si le serveur
// l'annonce. Le serveur, l'utilisateur borne, la présentation et l'imprimante ont leurs propres réglages
// (SettingsProvider, BorneReglages, ImprimanteReglages), partagés avec le code de la borne.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class PosConfig {
  /// Assistant de premier lancement terminé (sinon l'assistant s'ouvre au démarrage).
  final bool configure;

  /// Mobile money proposé au client si le module serveur B3 l'annonce (sinon « Payer en caisse » seul).
  final bool mobileMoney;

  const PosConfig({this.configure = false, this.mobileMoney = true});

  PosConfig copyWith({bool? configure, bool? mobileMoney}) =>
      PosConfig(configure: configure ?? this.configure, mobileMoney: mobileMoney ?? this.mobileMoney);
}

class PosReglages {
  PosReglages._();
  static const cleConfigure = 'prestigepos_configure_v1';
  static const cleMobileMoney = 'prestigepos_mobile_money_v1';

  static final ValueNotifier<PosConfig> courant = ValueNotifier(const PosConfig());

  static Future<PosConfig> charger() async {
    try {
      final p = await SharedPreferences.getInstance();
      courant.value = PosConfig(configure: p.getBool(cleConfigure) ?? false, mobileMoney: p.getBool(cleMobileMoney) ?? true);
    } catch (_) {
      courant.value = const PosConfig();
    }
    return courant.value;
  }

  static Future<void> enregistrer(PosConfig c) async {
    courant.value = c;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(cleConfigure, c.configure);
      await p.setBool(cleMobileMoney, c.mobileMoney);
    } catch (_) {}
  }
}
