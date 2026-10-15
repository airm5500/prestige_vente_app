// lib/prestigepos/impression/imprimante_page.dart
// PrestigePOS — réglages de l'imprimante de ticket (assistant de premier lancement et Administration) :
// type, papier 58 / 80 mm, Bluetooth (« Rechercher » : appairés + découverte, choix, « Ajouter », mémorisation),
// USB (OTG), réseau (IP:9100), options (QR natif / image, accents, coupe) et « Test d'impression ».
// Chaque changement est enregistré tout de suite (ImprimanteReglages).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/prestigepos/impression/escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_pos.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Contenu des réglages de l'imprimante (sans Scaffold : intégré à l'assistant et à la page d'administration).
class ImprimanteReglagesVue extends StatefulWidget {
  /// Nom de l'officine (imprimé sur le ticket d'essai).
  final String officine;

  /// Imprimante utilisée pour le test (tests) ; sinon ImprimantePos sur les réglages courants.
  final ImprimantePos Function()? imprimante;
  const ImprimanteReglagesVue({super.key, this.officine = '', this.imprimante});

  @override
  State<ImprimanteReglagesVue> createState() => _ImprimanteReglagesVueState();
}

class _ImprimanteReglagesVueState extends State<ImprimanteReglagesVue> {
  ImprimanteConfig get _c => ImprimanteReglages.courant.value;
  late final _hote = TextEditingController(text: _c.hote);
  late final _port = TextEditingController(text: '${_c.port}');

  bool _recherche = false;
  List<AppareilImprimante>? _trouves;
  AppareilImprimante? _choisi;
  String? _erreurRecherche;
  bool _btInactif = false;

  bool _test = false;
  String? _resultatTest;
  bool _testOk = false;

  PontImprimantes get _pont => PontImprimantes.instance;

  @override
  void dispose() {
    _hote.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _maj(ImprimanteConfig c) async {
    await ImprimanteReglages.enregistrer(c);
    if (mounted) setState(() => _resultatTest = null);
  }

  // --- Bluetooth -------------------------------------------------------------

  Future<void> _rechercherBluetooth() async {
    if (_recherche) return;
    setState(() {
      _recherche = true;
      _erreurRecherche = null;
      _btInactif = false;
      _trouves = null;
      _choisi = null;
    });
    try {
      if (!await _pont.autorisations()) throw EchecImpression('PERMISSION', EchecImpression.messagePour('PERMISSION'));
      // Appairés d'abord (immédiat), puis découverte.
      final appaires = await _pont.appaires();
      if (mounted) setState(() => _trouves = appaires);
      final tous = await _pont.rechercher();
      final liste = <AppareilImprimante>[
        ...{for (final a in [...appaires, ...tous]) a.adresse.toUpperCase(): a}.values,
      ]..sort((a, b) {
          int rang(AppareilImprimante x) => (x.imprimante ? 0 : 2) + (x.appaire ? 0 : 1);
          final r = rang(a).compareTo(rang(b));
          return r != 0 ? r : a.libelle.compareTo(b.libelle);
        });
      if (mounted) setState(() => _trouves = liste);
    } on EchecImpression catch (e) {
      if (mounted) {
        setState(() {
          _erreurRecherche = e.message;
          _btInactif = e.code == 'BT_INACTIF';
        });
      }
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  Future<void> _ajouter() async {
    final a = _choisi;
    if (a == null) return;
    await _maj(_c.ajouterBluetooth(a));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Imprimante « ${a.libelle} » ajoutée et choisie.')));
    }
  }

  // --- USB ---------------------------------------------------------------------

  Future<void> _rechercherUsb() async {
    if (_recherche) return;
    setState(() {
      _recherche = true;
      _erreurRecherche = null;
      _trouves = null;
    });
    try {
      final l = await _pont.usb();
      if (mounted) {
        setState(() {
          _trouves = l;
          if (l.isEmpty) _erreurRecherche = EchecImpression.messagePour('USB_ABSENT');
        });
      }
    } on EchecImpression catch (e) {
      if (mounted) setState(() => _erreurRecherche = e.message);
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  // --- Test ----------------------------------------------------------------------

  Future<void> _tester() async {
    if (_test) return;
    if (_c.type == TypeImprimante.reseau) await _enregistrerReseau();
    setState(() {
      _test = true;
      _resultatTest = null;
    });
    String? r;
    try {
      r = await (widget.imprimante?.call() ?? ImprimantePos()).tester(officine: widget.officine);
    } catch (e) {
      r = 'Test impossible : $e';
    }
    if (!mounted) return;
    setState(() {
      _test = false;
      _testOk = r == null;
      _resultatTest = r ?? 'Ticket d\'essai imprimé : vérifiez qu\'il est lisible (largeur, accents, QR).';
    });
  }

  Future<void> _enregistrerReseau() async {
    await ImprimanteReglages.enregistrer(_c.copyWith(hote: _hote.text, port: int.tryParse(_port.text.trim()) ?? ImprimanteConfig.portDefaut));
  }

  // --- Affichage -------------------------------------------------------------

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Pal.muted, letterSpacing: .4)),
      );

  Widget _message(String m, {bool ok = false, Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: ok ? const Color(0xFFE6F4EA) : const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
        child: Text(m, style: TextStyle(fontSize: 14.5, color: ok ? const Color(0xFF14532D) : const Color(0xFF7C2D12))),
      );

  Widget _appareil(AppareilImprimante a, {required bool selectionne, required VoidCallback onTap, Widget? fin, required String cle}) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        color: selectionne ? const Color(0xFFE3ECF7) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), side: BorderSide(color: selectionne ? Pal.navy : Pal.line, width: selectionne ? 2 : 1)),
        child: ListTile(
          key: ValueKey(cle),
          minVerticalPadding: 10,
          leading: Icon(a.imprimante ? Icons.print : Icons.bluetooth, color: Pal.navy),
          title: Text(a.libelle, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
          subtitle: Text('${a.adresse}${a.appaire ? ' · appairée' : ''}', style: const TextStyle(color: Pal.muted)),
          trailing: fin ?? (selectionne ? const Icon(Icons.check_circle, color: Pal.navy) : null),
          onTap: onTap,
        ),
      );

  List<Widget> _bluetooth(ImprimanteConfig c) => [
        _titre('Imprimante Bluetooth'),
        if (c.memorisees.isNotEmpty) ...[
          const Text('Imprimantes mémorisées (touchez pour choisir) :', style: TextStyle(color: Pal.muted)),
          const SizedBox(height: 6),
          for (final m in c.memorisees)
            _appareil(m,
                cle: 'imp-bt-memorisee-${m.adresse}',
                selectionne: c.bluetooth == m,
                onTap: () => _maj(c.ajouterBluetooth(m)),
                fin: IconButton(
                  tooltip: 'Oublier',
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                  onPressed: () => _maj(c.oublierBluetooth(m)),
                )),
        ] else
          const Text('Aucune imprimante mémorisée. Allumez l\'imprimante, puis « Rechercher ».', style: TextStyle(color: Pal.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          ElevatedButton.icon(
            key: const ValueKey('imp-bt-rechercher'),
            style: navyButton,
            onPressed: _recherche ? null : _rechercherBluetooth,
            icon: _recherche
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bluetooth_searching),
            label: Text(_recherche ? 'Recherche…' : 'Rechercher'),
          ),
          if (_btInactif)
            OutlinedButton.icon(
              key: const ValueKey('imp-bt-activer'),
              onPressed: () async {
                try {
                  await _pont.activerBluetooth();
                } catch (_) {}
              },
              icon: const Icon(Icons.bluetooth),
              label: const Text('Activer le Bluetooth'),
            ),
        ]),
        if (_erreurRecherche != null) _message(_erreurRecherche!, key: const ValueKey('imp-recherche-erreur')),
        if (_trouves != null) ...[
          const SizedBox(height: 10),
          Text(_trouves!.isEmpty ? 'Aucun appareil trouvé.' : 'Appareils trouvés (imprimantes d\'abord) :',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
          const SizedBox(height: 6),
          for (final a in _trouves!)
            _appareil(a, cle: 'imp-bt-trouve-${a.adresse}', selectionne: _choisi == a, onTap: () => setState(() => _choisi = a)),
          if (_trouves!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                key: const ValueKey('imp-bt-ajouter'),
                style: amberButton,
                onPressed: _choisi == null ? null : _ajouter,
                icon: const Icon(Icons.add),
                label: Text(_choisi == null ? 'Choisissez un appareil' : 'Ajouter « ${_choisi!.libelle} »'),
              ),
            ),
        ],
      ];

  List<Widget> _usb(ImprimanteConfig c) => [
        _titre('Imprimante USB (câble OTG)'),
        Text(c.usb == null ? 'Branchez l\'imprimante, puis « Rechercher ».' : 'Choisie : ${c.usb!.libelle}',
            style: const TextStyle(color: Pal.muted)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            key: const ValueKey('imp-usb-rechercher'),
            style: navyButton,
            onPressed: _recherche ? null : _rechercherUsb,
            icon: const Icon(Icons.usb),
            label: const Text('Rechercher'),
          ),
        ),
        if (_erreurRecherche != null) _message(_erreurRecherche!, key: const ValueKey('imp-recherche-erreur')),
        if (_trouves != null)
          for (final a in _trouves!)
            _appareil(a, cle: 'imp-usb-${a.adresse}', selectionne: c.usb == a, onTap: () => _maj(c.copyWith(type: TypeImprimante.usb, usb: a))),
      ];

  List<Widget> _reseau(ImprimanteConfig c) => [
        _titre('Imprimante réseau (Wi-Fi / Ethernet)'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: TextField(
              key: const ValueKey('imp-reseau-hote'),
              controller: _hote,
              keyboardType: TextInputType.url,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(labelText: 'Adresse IP', hintText: '192.168.1.80', border: OutlineInputBorder()),
              onSubmitted: (_) => _enregistrerReseau(),
              onEditingComplete: _enregistrerReseau,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              key: const ValueKey('imp-reseau-port'),
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
              onSubmitted: (_) => _enregistrerReseau(),
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Port 9100 (« RAW ») pour la plupart des imprimantes. Donnez-lui une adresse IP fixe.',
              style: TextStyle(fontSize: 12.5, color: Pal.muted)),
        ),
      ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ImprimanteConfig>(
        valueListenable: ImprimanteReglages.courant,
        builder: (context, c, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _titre('Type d\'imprimante'),
          for (final t in TypeImprimante.values)
            RadioListTile<TypeImprimante>(
              key: ValueKey('imp-type-${t.name}'),
              value: t,
              groupValue: c.type,
              title: Text(t.label),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() {
                _trouves = null;
                _erreurRecherche = null;
                _maj(c.copyWith(type: v));
              }),
            ),
          if (c.type != TypeImprimante.sunmi && c.type != TypeImprimante.automatique) ...[
            _titre('Largeur du papier'),
            SegmentedButton<int>(
              key: const ValueKey('imp-papier'),
              segments: const [
                ButtonSegment(value: 58, label: Text('58 mm'), icon: Icon(Icons.receipt)),
                ButtonSegment(value: 80, label: Text('80 mm'), icon: Icon(Icons.receipt_long)),
              ],
              selected: {c.papier},
              onSelectionChanged: (s) => _maj(c.copyWith(papier: s.first)),
            ),
          ],
          if (c.type == TypeImprimante.bluetooth) ..._bluetooth(c),
          if (c.type == TypeImprimante.usb) ..._usb(c),
          if (c.type == TypeImprimante.reseau) ..._reseau(c),
          if (c.type.externe) ...[
            _titre('Options'),
            SwitchListTile(
              key: const ValueKey('imp-qr-image'),
              contentPadding: EdgeInsets.zero,
              title: const Text('QR code en image'),
              subtitle: const Text('Pour les imprimantes qui n\'impriment pas le QR (ticket sans QR au test).'),
              value: c.qr == ModeQr.image,
              onChanged: (v) => _maj(c.copyWith(qr: v ? ModeQr.image : ModeQr.natif)),
            ),
            SwitchListTile(
              key: const ValueKey('imp-accents'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Imprimer les accents (page PC858)'),
              subtitle: const Text('Désactivé : « é » imprimé « e », lisible sur toutes les imprimantes.'),
              value: c.jeu == JeuCaracteres.pc858,
              onChanged: (v) => _maj(c.copyWith(jeu: v ? JeuCaracteres.pc858 : JeuCaracteres.ascii)),
            ),
            SwitchListTile(
              key: const ValueKey('imp-coupe'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Couper le papier'),
              subtitle: const Text('Imprimantes à couteau automatique.'),
              value: c.coupe,
              onChanged: (v) => _maj(c.copyWith(coupe: v)),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('imp-test'),
              style: outlineButton,
              onPressed: _test ? null : _tester,
              icon: _test ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print),
              label: const Text('Test d\'impression'),
            ),
          ),
          if (_resultatTest != null) _message(_resultatTest!, ok: _testOk, key: const ValueKey('imp-test-resultat')),
        ]),
      );
}
