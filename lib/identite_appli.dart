// lib/identite_appli.dart
// Prestige Mobile V3 (5.0.0) — identité de l'application : NOUVELLE application Android (com.dici.prestigemobile.v3),
// installable à côté de l'ancienne « Prestige Mobile » (com.dici.prestige_vente_app, fiche Sunmi gardée telle quelle
// pour les officines aux anciens serveurs). Voir docs/NOTE_VERSION_5.0.0.md.
//
// - [nomAppli] : nom affiché partout où l'application se nomme (lanceur : android:label du manifeste ; écrans de
//   lancement et de connexion, accueil sans officine, titre de la tâche Android, journal PDF, « Envoyé depuis … »).
//   Le contenu des messages envoyés au serveur (support : champ « application ») est INCHANGÉ (contrat du serveur).
// - [AncienneAppli] : l'ancienne application est-elle encore installée sur ce terminal ? (visibilité du paquet,
//   src/mobile/AndroidManifest.xml ; canal « prestige/pointage » de MainActivity, méthode estInstallee). Rien n'est lu
//   dans l'ancienne application : Android sépare les données de chaque application.
// - [BandeauAncienneAppli] : information affichée UNE fois sur l'écran de connexion (jusqu'à « Compris »).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nom de l'application (lanceur Android, écrans).
const nomAppli = 'Prestige Mobile V3';

/// Ancienne Prestige Mobile (même terminal) : détection seulement, une fois par lancement.
class AncienneAppli {
  AncienneAppli._();

  static const paquet = 'com.dici.prestige_vente_app';
  static const _canal = MethodChannel('prestige/pointage');

  /// Préférence : bandeau déjà lu (« Compris »).
  static const prefVu = 'v3_ancienne_appli_bandeau_vu';

  static const message = 'Ancienne application installée : synchronisez ses ventes hors ligne avant de la désinstaller.';

  /// Remplaçable pour les tests. Sans canal natif (tests, PrestigePOS, Prestige Pointage) : faux.
  static Future<bool> Function() detecteur = () async => await _canal.invokeMethod<bool>('estInstallee', {'paquet': paquet}) ?? false;

  /// Vrai si le bandeau doit être affiché : ancienne application installée et bandeau pas encore lu.
  static Future<bool> aAfficher() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(prefVu) ?? false) return false;
      return await detecteur();
    } catch (_) {
      return false; // jamais bloquant
    }
  }

  /// « Compris » : plus jamais affiché sur ce terminal.
  static Future<void> marquerVu() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefVu, true);
    } catch (_) {}
  }

  @visibleForTesting
  static void reinitialiser() {
    detecteur = () async => await _canal.invokeMethod<bool>('estInstallee', {'paquet': paquet}) ?? false;
  }
}

/// Bandeau d'information de l'écran de connexion (rien si l'ancienne application n'est pas installée).
class BandeauAncienneAppli extends StatefulWidget {
  const BandeauAncienneAppli({super.key});

  @override
  State<BandeauAncienneAppli> createState() => _BandeauAncienneAppliState();
}

class _BandeauAncienneAppliState extends State<BandeauAncienneAppli> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    AncienneAppli.aAfficher().then((v) {
      if (mounted && v) setState(() => _visible = true);
    });
  }

  Future<void> _compris() async {
    setState(() => _visible = false);
    await AncienneAppli.marquerVu();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const Key('bandeau_ancienne_appli'),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF7DD3FC)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: Color(0xFF075985)),
            SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(AncienneAppli.message, style: TextStyle(color: Color(0xFF0C2A3F), fontSize: 13.5)),
              ),
            ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('bandeau_ancienne_appli_compris'),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48), foregroundColor: const Color(0xFF075985)),
              onPressed: _compris,
              child: const Text('Compris', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
