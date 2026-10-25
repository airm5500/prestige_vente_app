// lib/main_pos.dart
// Point d'entrée de PrestigePOS (saveur Android `pos`) :
//   flutter run --flavor pos -t lib/main_pos.dart
//   flutter build apk --release --flavor pos -t lib/main_pos.dart
// Prestige Mobile garde son point d'entrée lib/main.dart (saveur `mobile`, par défaut), inchangé.
// PrestigePOS ne charge que ce dont la borne a besoin : pas de base SQLite (aucune vente hors ligne à la borne),
// pas de copie du catalogue, pas de pointage ; la surveillance du serveur et le journal restent en mémoire.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/horsligne/catalogue_sync.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/vente_hors_ligne.dart';
import 'package:prestige_vente_app/horsligne/ventes_sync.dart';
import 'package:prestige_vente_app/images/images_reglages.dart';
import 'package:prestige_vente_app/images/produit_images.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/prestigepos/demarrage_auto.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/pos_app.dart';
import 'package:prestige_vente_app/prestigepos/pos_reglages.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/version_app.dart';

/// Initialisation commune (appli et tests e2e) : réglages lus, services de la borne en mémoire.
Future<void> initialiserPrestigePos() async {
  await initializeDateFormatting('fr_FR', null);
  await TailleEcranReglage.charger();
  await SearchModePrefs.load();
  await BorneReglages.charger();
  await ImagesReglages.charger();
  await ImprimanteReglages.charger();
  final pos = await PosReglages.charger();
  // B3 : mobile money proposé si le serveur l'annonce (réglage de PrestigePOS, activé par défaut).
  PaiementsMobileReglages.actif.value = pos.mobileMoney;
  final store = MemoryLocalStore();
  HorsLigne.instance = HorsLigne(
    monitor: ServerMonitor(),
    store: store,
    sync: CatalogueSync(store: store),
    ventes: FileVentesHL(store: MemoryVentesHLStore()),
  );
  JournalTerminal.instance = JournalTerminal();
  // 1.5.0 : nom de cet appareil (en-tête X-Poste vers Prestige) ; marque et modèle (nom par défaut) lus par main().
  await NomAppareil.instance.charger();
  PosApp.installer();
  // 1.1.0 : démarrage automatique — Android remis d'accord avec le réglage (sans attendre).
  unawaited(DemarrageAuto.synchroniser());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VersionApp.charger();
  await initialiserPrestigePos();
  // 1.5.0 : marque et modèle de l'appareil (nom par défaut de X-Poste), par le canal natif existant.
  await JournalTerminal.instance.chargerIdentite(materiel: FingerprintService.hardwareInfo);
  ProduitImages.instance.dossier = () async => Directory('${(await getApplicationSupportDirectory()).path}/images_produits');
  unawaited(ProduitImages.instance.init());
  // Plein écran dès le lancement.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const PrestigePosApp());
}
