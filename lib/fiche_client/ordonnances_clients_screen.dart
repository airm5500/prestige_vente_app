// lib/fiche_client/ordonnances_clients_screen.dart
// Menu « Ordonnances des clients » (même nom que l'écran web) : onglet « Fiche client ».
// Droits lus sur GET v1/ordonnance-client/droits : consultation (P_ORDONNANCE_CLIENT) obligatoire, saisie
// (allergies, terrains, mesures) seulement avec P_ORDONNANCE_CLIENT_MAJ. Le serveur revérifie chaque appel.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_api.dart';
import 'package:prestige_vente_app/fiche_client/fiche_client_tab.dart';
import 'package:prestige_vente_app/serveur/client_contexte.dart';
import 'package:prestige_vente_app/serveur/erreur_vue.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class OrdonnancesClientsScreen extends StatefulWidget {
  final FicheClientApi? api;
  const OrdonnancesClientsScreen({super.key, this.api});

  @override
  State<OrdonnancesClientsScreen> createState() => _OrdonnancesClientsScreenState();
}

class _OrdonnancesClientsScreenState extends State<OrdonnancesClientsScreen> {
  late final FicheClientApi _api = widget.api ?? FicheClientApi(clientPrestige(context));
  DroitsOrdonnances? _droits;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _lireDroits());
  }

  Future<void> _lireDroits() async {
    if (!mounted) return;
    setState(() => _erreur = null);
    try {
      final d = await _api.droits();
      if (mounted) setState(() => _droits = d);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _droits;
    final Widget corps;
    if (d == null && _erreur != null) {
      corps = ErreurVue(erreur: _erreur!, onReessayer: _lireDroits);
    } else if (d == null) {
      corps = const Center(child: CircularProgressIndicator());
    } else if (!menuOrdonnancesVisible(d)) {
      corps = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Votre profil ne donne pas accès aux ordonnances des clients.', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted)),
        ),
      );
    } else {
      corps = FicheClientTab(api: _api, modifier: saisieFicheClientAutorisee(d));
    }
    return Scaffold(
      backgroundColor: Pal.page,
      body: Column(children: [
        NavyHeader(
          title: 'Ordonnances des clients',
          subtitle: d == null ? null : (saisieFicheClientAutorisee(d) ? 'Consultation et saisie' : 'Consultation seule'),
          children: [SegmentedPills(labels: const ['Fiche client'], selected: 0, onSelected: (_) {})],
        ),
        Expanded(child: corps),
      ]),
    );
  }
}
