// lib/borne/borne_client.dart
// PrestigePOS 1.11.0 (décision du pharmacien du 14/11/2026) — client FACULTATIF de la vente comptant de la borne,
// mêmes règles que Prestige Mobile 4.13.0, adaptées à la borne vue par les clients :
//  - « Ajouter mon nom (facultatif) » dans le panier, EN LIGNE seulement (passerelle avec ClientVenteGateway) ;
//  - page de la borne : recherche (≥ 3 caractères ou numéro de 4 chiffres, GET v1/client/lambda), grandes tuiles de
//    résultats (nom, prénom, téléphone), « Nouveau client » (nom, prénom, téléphone ; clavier nom / téléphone ;
//    POST v1/client/add/lambda, refus → msg tel quel) ; le choix ramène au panier et EFFACE la liste et le texte ;
//  - client choisi : nom et croix ; 1er appui → croix rouge, 2e appui → retiré (pas de fenêtre) ;
//  - la prévente n'existe sur le serveur qu'à « Payer » : le client est rattaché À LA CRÉATION de la prévente
//    (POST v1/vente/update/client, BorneService.creerPrevente) ; le ticket indique « Client associé » seulement après
//    success:true, sinon le msg du serveur (la prévente reste valable, sans client) ;
//  - confidentialité : [BorneClientEtat.vider] à chaque retour à l'accueil (fin, abandon, inactivité, serveur
//    perdu) : ni nom, ni téléphone, ni résultat d'un client précédent ; rien dans aucun journal.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/borne/borne_widgets.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// État du client de la vente en cours à la borne (oublié à chaque retour à l'accueil).
class BorneClientEtat extends ChangeNotifier {
  final ClientVenteGateway? gateway;
  BorneClientEtat(this.gateway);

  ClientVente? _choisi;
  ClientVente? get choisi => _choisi;

  /// Résultats affichés (null = aucune recherche) ; vidés au choix et à l'accueil.
  List<ClientVente>? resultats;
  String? erreur;
  bool cherche = false;
  bool occupe = false;
  int _n = 0;

  bool get disponible => gateway != null;

  void choisir(ClientVente c) {
    _choisi = c;
    resultats = null;
    erreur = null;
    notifyListeners();
  }

  void retirer() {
    _choisi = null;
    notifyListeners();
  }

  /// Tout oublier (fin ou abandon de la vente) : client, résultats, erreurs, recherche en cours.
  void vider() {
    _n++;
    _choisi = null;
    resultats = null;
    erreur = null;
    cherche = false;
    occupe = false;
    notifyListeners();
  }

  Future<void> chercher(String texte) async {
    final g = gateway;
    if (g == null || !rechercheClientPossible(texte)) {
      _n++;
      resultats = null;
      cherche = false;
      notifyListeners();
      return;
    }
    final n = ++_n;
    cherche = true;
    erreur = null;
    notifyListeners();
    final r = await g.rechercherClientsVente(texte);
    if (n != _n) return;
    cherche = false;
    if (r case VenteOk(:final value)) {
      resultats = value;
    } else {
      resultats = null;
      erreur = venteMessage(r.message);
    }
    notifyListeners();
  }

  /// Création (en ligne) ; le client créé est choisi (rattaché à la création de la prévente).
  Future<bool> creer({required String nom, required String prenom, required String telephone}) async {
    final g = gateway;
    if (g == null || occupe) return false;
    if (nom.trim().isEmpty && prenom.trim().isEmpty) {
      erreur = 'Le nom ou le prénom est obligatoire.';
      notifyListeners();
      return false;
    }
    final n = _n;
    occupe = true;
    erreur = null;
    notifyListeners();
    final r = await g.creerClientVente(nom: nom, prenom: prenom, telephone: telephone);
    if (n != _n) return false; // vente abandonnée entre-temps
    occupe = false;
    if (r case VenteOk(:final value)) {
      choisir(value);
      return true;
    }
    erreur = venteMessage(r.message);
    notifyListeners();
    return false;
  }
}

/// Zone du panier : « Ajouter mon nom (facultatif) », ou le client choisi avec sa croix.
class BorneClientZone extends StatefulWidget {
  final BorneClientEtat etat;
  final VoidCallback onOuvrir;
  final VoidCallback onActivite;
  final bool enabled;
  const BorneClientZone({super.key, required this.etat, required this.onOuvrir, required this.onActivite, this.enabled = true});

  @override
  State<BorneClientZone> createState() => _BorneClientZoneState();
}

class _BorneClientZoneState extends State<BorneClientZone> {
  bool _arme = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _croix() {
    widget.onActivite();
    if (!_arme) {
      setState(() => _arme = true);
      _t?.cancel();
      _t = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _arme = false);
      });
      return;
    }
    _t?.cancel();
    setState(() => _arme = false);
    widget.etat.retirer();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.etat.choisi;
    if (c == null) {
      return SizedBox(
        width: double.infinity,
        child: BorneBouton('AJOUTER MON NOM (FACULTATIF)',
            key: const ValueKey('borne-client-ouvrir'), icon: Icons.person_add_alt_1, contour: true, onPressed: widget.enabled ? widget.onOuvrir : null),
      );
    }
    return Container(
      key: const ValueKey('borne-client-zone'),
      constraints: const BoxConstraints(minHeight: borneToucheMin + 4),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(color: const Color(0xFFEFF4FA), borderRadius: BorderRadius.circular(14), border: Border.all(color: Pal.navy, width: 2)),
      child: Row(children: [
        const Icon(Icons.person, size: 28, color: Pal.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(c.nomComplet,
                key: const ValueKey('borne-client-nom'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.ink)),
            Text(_arme ? 'Touchez encore la croix pour retirer votre nom' : 'Associé à la vente quand vous payez',
                key: ValueKey(_arme ? 'borne-client-confirmer' : 'borne-client-info'),
                maxLines: 2,
                style: TextStyle(fontSize: 14, color: _arme ? const Color(0xFFB91C1C) : Pal.muted, fontWeight: _arme ? FontWeight.w700 : FontWeight.normal)),
          ]),
        ),
        IconButton(
          key: const ValueKey('borne-client-retirer'),
          tooltip: _arme ? 'Toucher encore pour retirer' : 'Retirer mon nom',
          constraints: const BoxConstraints(minWidth: borneToucheMin + 8, minHeight: borneToucheMin + 4),
          iconSize: 34,
          onPressed: widget.enabled ? _croix : null,
          icon: Icon(_arme ? Icons.cancel : Icons.close, color: _arme ? const Color(0xFFB91C1C) : Pal.muted),
        ),
      ]),
    );
  }
}

/// Page de la borne : recherche, résultats en grandes tuiles, nouveau client.
class BorneClientVue extends StatefulWidget {
  final BorneClientEtat etat;
  final VoidCallback onRetour;
  final VoidCallback onActivite;
  final Duration antiRebond;
  const BorneClientVue({super.key, required this.etat, required this.onRetour, required this.onActivite, this.antiRebond = const Duration(milliseconds: 400)});

  @override
  State<BorneClientVue> createState() => _BorneClientVueState();
}

class _BorneClientVueState extends State<BorneClientVue> {
  final _recherche = TextEditingController();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _tel = TextEditingController();
  Timer? _rebond;
  bool _nouveau = false;

  BorneClientEtat get _e => widget.etat;

  @override
  void initState() {
    super.initState();
    _e.addListener(_maj);
  }

  @override
  void dispose() {
    _e.removeListener(_maj);
    _rebond?.cancel();
    for (final c in [_recherche, _nom, _prenom, _tel]) {
      c.dispose();
    }
    super.dispose();
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  void _frappe(String t) {
    widget.onActivite();
    _rebond?.cancel();
    _rebond = Timer(widget.antiRebond, () => _e.chercher(t));
    setState(() {});
  }

  void _choisir(ClientVente c) {
    widget.onActivite();
    _e.choisir(c);
    widget.onRetour();
  }

  Future<void> _creer() async {
    widget.onActivite();
    final ok = await _e.creer(nom: _nom.text, prenom: _prenom.text, telephone: _tel.text);
    if (ok && mounted) widget.onRetour();
  }

  InputDecoration _deco(String libelle, IconData icone) => InputDecoration(
        labelText: libelle,
        labelStyle: const TextStyle(fontSize: 18),
        prefixIcon: Icon(icone, size: 28, color: Pal.navy),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  Widget _champ(String cle, TextEditingController c, String libelle, IconData icone,
          {TextInputType clavier = TextInputType.name, TextCapitalization casse = TextCapitalization.characters, List<TextInputFormatter> formats = const []}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: ValueKey(cle),
          controller: c,
          enabled: !_e.occupe,
          keyboardType: clavier,
          textCapitalization: casse,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [LengthLimitingTextInputFormatter(50), ...formats],
          onChanged: (_) => widget.onActivite(),
          style: const TextStyle(fontSize: 20, color: Pal.ink),
          decoration: _deco(libelle, icone),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final r = e.resultats;
    final t = _recherche.text.trim();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('borne-client-retour'),
            style: TextButton.styleFrom(minimumSize: const Size(borneToucheMin * 2, borneToucheMin), foregroundColor: Pal.navy),
            onPressed: () {
              widget.onActivite();
              widget.onRetour();
            },
            icon: const Icon(Icons.arrow_back, size: 26),
            label: const Text('Retour au panier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      Expanded(
        child: ListView(key: const ValueKey('borne-client-page'), padding: const EdgeInsets.fromLTRB(16, 6, 16, 20), children: [
          const Text('Votre nom (facultatif)', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Pal.ink)),
          const SizedBox(height: 4),
          const Text('Pour retrouver vos achats à la pharmacie. Vous pouvez payer sans.', style: TextStyle(fontSize: 16, color: Pal.muted)),
          if (!_nouveau) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('borne-client-recherche'),
              controller: _recherche,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [LengthLimitingTextInputFormatter(50)],
              onChanged: _frappe,
              style: const TextStyle(fontSize: 20, color: Pal.ink),
              decoration: _deco('Votre nom ou votre numéro', Icons.search).copyWith(
                suffixIcon: e.cherche ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))) : null,
              ),
            ),
            if (t.isNotEmpty && !rechercheClientPossible(t))
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Au moins 3 lettres, ou 4 chiffres du numéro.', key: ValueKey('borne-client-aide'), style: TextStyle(fontSize: 15, color: Pal.muted)),
              ),
          ],
          if (e.erreur != null)
            Container(
              key: const ValueKey('borne-client-erreur'),
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
              child: Text(e.erreur!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 16)),
            ),
          if (r != null && !_nouveau) ...[
            const SizedBox(height: 10),
            if (r.isEmpty) const Text('Aucun client trouvé.', key: ValueKey('borne-client-aucun'), style: TextStyle(fontSize: 16, color: Pal.muted)),
            for (final c in r)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Pal.line, width: 1.5)),
                  child: InkWell(
                    key: ValueKey('borne-client-resultat-${c.id}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _choisir(c),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: borneToucheMin + 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(children: [
                          const Icon(Icons.person_outline, size: 30, color: Pal.navy),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(c.nomComplet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Pal.ink)),
                              if (c.telephone.isNotEmpty) Text(c.telephone, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, color: Pal.muted)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, size: 30, color: Pal.navy),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (!_nouveau)
            SizedBox(
              width: double.infinity,
              child: BorneBouton('JE SUIS UN NOUVEAU CLIENT',
                  key: const ValueKey('borne-client-nouveau'),
                  icon: Icons.person_add_alt_1,
                  contour: true,
                  onPressed: () {
                    widget.onActivite();
                    setState(() {
                      _nouveau = true;
                      e.erreur = null;
                      if (_nom.text.isEmpty && t.isNotEmpty && !RegExp(r'^[\d\s+.\-]+$').hasMatch(t)) _nom.text = t.toUpperCase();
                      if (_tel.text.isEmpty && RegExp(r'^[\d\s+.\-]{4,}$').hasMatch(t)) _tel.text = t;
                    });
                  }),
            )
          else ...[
            _champ('borne-client-nom-saisi', _nom, 'Nom', Icons.badge_outlined),
            _champ('borne-client-prenom-saisi', _prenom, 'Prénom', Icons.badge_outlined, casse: TextCapitalization.words),
            _champ('borne-client-telephone-saisi', _tel, 'Téléphone', Icons.phone,
                clavier: TextInputType.phone, casse: TextCapitalization.none, formats: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +.\-]'))]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: BorneBouton('VALIDER MON NOM', key: const ValueKey('borne-client-creer'), icon: Icons.check, occupe: e.occupe, onPressed: e.occupe ? null : _creer),
            ),
          ],
        ]),
      ),
    ]);
  }
}
