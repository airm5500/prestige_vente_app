// lib/prestigepos/pos_demarrage_page.dart
// PrestigePOS 1.1.0 — Administration › « Démarrage automatique » (ouverte après le code administrateur) :
// réglage « Démarrer automatiquement avec l'appareil » (désactivé par défaut), état réel d'Android (accueil,
// propriétaire de l'appareil), choix de l'application d'accueil, « Revenir à Android ». Mode d'emploi :
// docs/prestigepos/README.md › « Démarrage automatique ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/prestigepos/demarrage_auto.dart';
import 'package:prestige_vente_app/prestigepos/pos_styles.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class PosDemarrageAutoPage extends StatefulWidget {
  const PosDemarrageAutoPage({super.key});

  @override
  State<PosDemarrageAutoPage> createState() => _PosDemarrageAutoPageState();
}

class _PosDemarrageAutoPageState extends State<PosDemarrageAutoPage> with WidgetsBindingObserver {
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DemarrageAuto.lire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Retour de l'écran d'Android « Application d'accueil » : état relu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) DemarrageAuto.lire();
  }

  Future<void> _activer(bool v) async {
    if (_occupe) return; // anti double appui
    setState(() => _occupe = true);
    await DemarrageAuto.activer(v);
    if (mounted) setState(() => _occupe = false);
  }

  Widget _ligne(String cle, bool ok, String texte) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, key: ValueKey('$cle-${ok ? 'oui' : 'non'}'), color: ok ? Pal.green : Pal.muted, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 15, color: Pal.ink))),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('pos-demarrage-page'),
        backgroundColor: Pal.page,
        appBar: AppBar(backgroundColor: Pal.navy, foregroundColor: Colors.white, title: const Text('Démarrage automatique')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ValueListenableBuilder<EtatDemarrage>(
              valueListenable: DemarrageAuto.courant,
              builder: (context, e, _) => ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Pal.line)),
                  child: SwitchListTile(
                    key: const ValueKey('pos-demarrage-auto'),
                    value: e.actif,
                    onChanged: _occupe ? null : _activer,
                    title: const Text('Démarrer automatiquement avec l\'appareil',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Pal.ink)),
                    subtitle: const Text('Après une coupure de courant ou un redémarrage, la borne se rouvre seule, en mode kiosque.',
                        style: TextStyle(color: Pal.muted)),
                  ),
                ),
                if (e.actif) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('pos-demarrage-etat'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _ligne('pos-demarrage-accueil', e.accueilParDefaut, 'PrestigePOS est l\'application d\'accueil (« Toujours »)'),
                      _ligne('pos-demarrage-proprietaire', e.proprietaire,
                          e.proprietaire ? 'Propriétaire de l\'appareil : verrouillage sans confirmation' : 'Propriétaire de l\'appareil : non (facultatif, voir le mode d\'emploi)'),
                      if (e.conseil.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(e.conseil, key: const ValueKey('pos-demarrage-conseil'), style: const TextStyle(color: Color(0xFF7C2D12), fontWeight: FontWeight.w600)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 10),
                  if (!e.accueilParDefaut)
                    ElevatedButton.icon(
                      key: const ValueKey('pos-demarrage-choisir-accueil'),
                      style: posBoutonBleu,
                      onPressed: DemarrageAuto.ouvrirChoixAccueil,
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('Choisir PrestigePOS comme accueil'),
                    ),
                ],
                if (e.proprietaire) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('pos-demarrage-retirer-proprietaire'),
                    style: posBoutonContour,
                    onPressed: _occupe ? null : DemarrageAuto.retirerProprietaire,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Retirer le propriétaire de l\'appareil'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('pos-demarrage-android'),
                  style: posBoutonContour,
                  onPressed: _occupe ? null : DemarrageAuto.revenirAndroid,
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Revenir à Android'),
                ),
                const SizedBox(height: 6),
                const Text('Désactive le démarrage automatique, arrête le verrouillage et ouvre l\'accueil d\'Android.',
                    style: TextStyle(color: Pal.muted, fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
}
