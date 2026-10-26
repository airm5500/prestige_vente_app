// lib/main_pointage.dart
// Point d'entrée de Prestige Pointage (saveur Android `pointage`, com.dici.prestigepointage, demande 57) :
//   flutter run --flavor pointage -t lib/main_pointage.dart
//   flutter build apk --release --flavor pointage -t lib/main_pointage.dart
// Prestige Mobile garde son point d'entrée lib/main.dart (saveur `mobile`, par défaut), inchangé.
// Ne charge que le pointage : copie des employés et file des pointages (SQLite), journal du terminal, nom de
// l'appareil (X-Poste), identité de la borne (stockage sécurisé), identification et photo de contrôle.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/horsligne/local_store.dart';
import 'package:prestige_vente_app/prestigepointage/controleur_borne.dart';
import 'package:prestige_vente_app/prestigepointage/identite_borne.dart';
import 'package:prestige_vente_app/prestigepointage/pointage_app.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/rh_store.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/ui/taille_ecran.dart';
import 'package:prestige_vente_app/version_app.dart';

/// Initialisation commune (application et tests e2e).
Future<void> initialiserPrestigePointage({LocalStore? store, CoffreBorne? coffre, PhotoControle? photos, IdentificationEmploye? identification}) async {
  await initializeDateFormatting('fr_FR', null);
  await TailleEcranReglage.charger();
  final local = store ?? SqfliteLocalStore();
  JournalTerminal.instance = local is SqfliteLocalStore ? JournalTerminal.app(local) : JournalTerminal();
  await NomAppareil.instance.charger();
  final ph = photos ?? (PhotoControle.instance ??= PhotoControle());
  PointageApp.controleur = ControleurBorne(
    coffre: coffre ?? const CoffreBorneSecurise(),
    store: local is SqfliteLocalStore ? SqfliteRhStore(local) : MemoryRhStore(),
    identification: identification ?? IdentificationEmploye(),
    photos: ph,
  );
  unawaited(ph.registre.charger().catchError((_) {}));
  await PointageApp.controleur.charger();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await VersionApp.charger();
  await initialiserPrestigePointage();
  // Marque et modèle (nom par défaut de l'appareil), par le canal natif existant.
  await JournalTerminal.instance.chargerIdentite(materiel: FingerprintService.hardwareInfo);
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  runApp(const PrestigePointageApp());
}
