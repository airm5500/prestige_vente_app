// lib/ordonnances/o4/apprentissages_screen.dart
// Étape O4 : gestion des apprentissages (Réglages › Ventes › Ordonnances, code administrateur) :
// liste « segment lu → produit » (confirmations, contradictions, date), recherche, oublier une association,
// tout réinitialiser ; état du partage entre terminaux.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/ordonnances/o4/apprentissage_o4.dart';
import 'package:prestige_vente_app/ordonnances/o4/partage_o4.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

class ApprentissagesScreen extends StatefulWidget {
  /// Apprentissages (tests) ; sinon ceux de l'appareil.
  final ApprentissagesO4? apprentissages;
  const ApprentissagesScreen({super.key, this.apprentissages});

  @override
  State<ApprentissagesScreen> createState() => _ApprentissagesScreenState();
}

class _ApprentissagesScreenState extends State<ApprentissagesScreen> {
  ApprentissagesO4? _a;
  final _recherche = TextEditingController();

  @override
  void initState() {
    super.initState();
    final a = widget.apprentissages;
    if (a != null) {
      _brancher(a);
    } else {
      ApprentissagesO4.charger().then((a) {
        if (mounted) _brancher(a);
      });
    }
    PartageO4.instance.charger().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _brancher(ApprentissagesO4 a) {
    setState(() => _a = a);
    a.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _a?.removeListener(_maj);
    _recherche.dispose();
    super.dispose();
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<bool> _confirmer(String titre, String texte) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titre),
          content: Text(texte),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirmer')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final liste = a == null ? const <AssociationApprise>[] : a.rechercher(_recherche.text);
    final partage = PartageO4.instance;
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Pal.navy,
        title: const Text('Apprentissages ordonnances', style: TextStyle(fontWeight: FontWeight.bold, color: Pal.navy)),
        actions: [
          if (a != null && a.nombre > 0)
            IconButton(
              key: const Key('appr_reinitialiser'),
              tooltip: 'Tout réinitialiser',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await _confirmer('Tout oublier ?', 'Les ${a.nombre} associations apprises sur cet appareil seront effacées. '
                    'Les autres terminaux gardent les leurs.')) {
                  await a.reinitialiser();
                }
              },
            ),
        ],
      ),
      body: ContentWidth(
        child: a == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: [
                const Text(
                  'Chaque produit validé par le pharmacien pour une ligne lue est retenu : « texte lu → produit ». '
                  'Seul le nom du médicament lu est gardé (jamais le texte complet de l\'ordonnance). Après '
                  '${ApprentissagesO4.confirmationsSures} validations, la proposition devient « sûre » ; choisir un autre produit '
                  'pour le même texte la contredit et lui fait perdre sa priorité.',
                  style: TextStyle(fontSize: 12.5, color: Pal.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  partage.actif
                      ? 'Partagé avec les autres terminaux${partage.enAttente.value > 0 ? ' (${partage.enAttente.value} en attente d\'envoi)' : ''}.'
                      : (partage.capacite.value == false
                          ? 'Le serveur ne gère pas le partage : apprentissages de cet appareil seulement.'
                          : 'Partage désactivé : apprentissages de cet appareil seulement.'),
                  key: const Key('appr_partage'),
                  style: const TextStyle(fontSize: 12.5, color: Pal.navy),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('appr_recherche'),
                  controller: _recherche,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher (texte lu, produit, CIP)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${liste.length} association(s)', key: const Key('appr_compte'), style: const TextStyle(color: Pal.muted)),
                for (final x in liste)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: ListTile(
                      dense: true,
                      title: Text('« ${x.segment} » → ${x.nom.isEmpty ? x.produitId : x.nom}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: x.active ? Pal.ink : Pal.muted)),
                      subtitle: Text(
                        '${x.confirmations} validation(s)'
                        '${x.contradictions > 0 ? ' · ${x.contradictions} contradiction(s)' : ''}'
                        '${x.cip.isNotEmpty ? ' · CIP ${x.cip}' : ''} · ${_date(x.maj)}'
                        '${x.sure ? ' · sûr' : (x.active ? '' : ' · inactif')}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Oublier',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await _confirmer('Oublier cette association ?', '« ${x.segment} » → ${x.nom}')) await a.oublier(x);
                        },
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}
