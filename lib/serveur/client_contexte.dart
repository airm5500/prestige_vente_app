// lib/serveur/client_contexte.dart
// Client JSON des modules Réserve / Analyse posologie / Fiche client, à l'adresse du serveur réglée dans l'appli.
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/client_prestige.dart';

ClientPrestige clientPrestige(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  return ClientPrestige(() => settings.baseUrl);
}
