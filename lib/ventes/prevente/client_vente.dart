// lib/ventes/prevente/client_vente.dart
// 4.13.0 — Client d'une vente COMPTANT (demande du 13/11/2026, plan du 12/11 point 8), facultatif :
//  - zone « Client » de l'écran de vente (vente créée sur le serveur, en ligne) : « Client (facultatif) » ; client
//    choisi : son nom, son téléphone et une croix ; 1er appui sur la croix → elle passe au rouge, 2e appui → retrait
//    (clientId:null), sans fenêtre de confirmation ; la croix redevient grise au bout de quelques secondes ;
//  - page de recherche : à partir de 3 caractères ou d'un numéro de 4 chiffres (GET v1/client/lambda), résultats
//    nom, prénom, téléphone ; « Nouveau client » (nom, prénom, téléphone ; POST v1/client/add/lambda) ;
//  - choisir ou créer → rattachement immédiat (POST v1/vente/update/client) ; le nom n'est affiché qu'après
//    `success:true` ; un refus affiche le `msg` du serveur tel quel et garde l'état précédent ; 403 `interdit` : msg,
//    sans déconnexion ; 409 `sessionChangee` : retour à l'accueil (lib/connexion/changement_utilisateur.dart).
// Confidentialité : ni le nom, ni le téléphone, ni le texte cherché ne sont écrits dans un journal (rien dans la console,
// les routes du client ne sont pas dans le journal du terminal, les adresses du support sont sans paramètres).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/prevente/vente_controller.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Délai pendant lequel la croix reste « armée » (rouge) après le 1er appui.
const delaiCroixRouge = Duration(seconds: 4);

/// Zone « Client » de la vente comptant en cours.
class ClientVenteZone extends StatefulWidget {
  final VenteController controller;

  /// Actions possibles (pas pendant un encaissement).
  final bool enabled;
  const ClientVenteZone({super.key, required this.controller, this.enabled = true});

  @override
  State<ClientVenteZone> createState() => _ClientVenteZoneState();
}

class _ClientVenteZoneState extends State<ClientVenteZone> {
  bool _arme = false;
  Timer? _desarmer;

  VenteController get _c => widget.controller;

  @override
  void didUpdateWidget(covariant ClientVenteZone old) {
    super.didUpdateWidget(old);
    if (_arme && _c.client == null) _annulerArme();
  }

  @override
  void dispose() {
    _desarmer?.cancel();
    super.dispose();
  }

  void _annulerArme() {
    _desarmer?.cancel();
    _desarmer = null;
    _arme = false;
  }

  bool get _actif => widget.enabled && _c.clientDisponible && !_c.busy;

  Future<void> _ouvrir() async {
    if (!_actif) return;
    setState(_annulerArme);
    final choisi = await Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: 'ClientVentePage'),
      builder: (_) => ClientVentePage(controller: _c),
    ));
    if (choisi == true && mounted) showVenteSnack(context, 'Client associé à la vente.', color: Colors.green.shade700);
  }

  Future<void> _croix() async {
    if (!_actif) return;
    if (!_arme) {
      setState(() {
        _arme = true;
        _desarmer?.cancel();
        _desarmer = Timer(delaiCroixRouge, () {
          if (mounted) setState(_annulerArme);
        });
      });
      return;
    }
    setState(_annulerArme);
    final r = await _c.retirerClient();
    if (!mounted) return;
    if (r.isOk) {
      showVenteSnack(context, 'Client retiré de la vente.');
    } else {
      showVenteFailure(context, r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final client = c.client;
    final nonLu = c.clientNonLu;
    final Widget contenu;
    if (client != null) {
      contenu = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(client.nomComplet,
            key: const ValueKey('client-vente-nom'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Pal.ink)),
        if (_arme)
          Text('Touchez encore la croix pour retirer le client',
              key: const ValueKey('client-vente-confirmer'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600))
        else if (client.telephone.isNotEmpty)
          Text(client.telephone,
              key: const ValueKey('client-vente-telephone-affiche'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Pal.muted)),
      ]);
    } else if (nonLu != null) {
      contenu = Text('Client de la vente non relu : ${venteMessage(nonLu)}',
          key: const ValueKey('client-vente-non-lu'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: Colors.red.shade700));
    } else {
      contenu = const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Client (facultatif)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Pal.navy)),
        Text('Rechercher ou créer', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Pal.muted)),
      ]);
    }
    final actif = _actif;
    return Container(
      key: const ValueKey('client-vente-zone'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('client-vente-ouvrir'),
          borderRadius: BorderRadius.circular(12),
          onTap: actif && nonLu == null ? _ouvrir : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(children: [
              const SizedBox(width: 10),
              Icon(client != null ? Icons.person : Icons.person_add_alt_1_outlined, size: 22, color: client != null ? Pal.navy : Pal.muted),
              const SizedBox(width: 10),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: contenu)),
              if (nonLu != null)
                TextButton(
                  key: const ValueKey('client-vente-relire'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Pal.navy),
                  onPressed: c.busy ? null : c.relireClient,
                  child: const Text('Réessayer'),
                )
              else if (client != null && c.clientDisponible)
                IconButton(
                  key: const ValueKey('client-vente-retirer'),
                  tooltip: _arme ? 'Toucher encore pour retirer le client' : 'Retirer le client',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: actif ? _croix : null,
                  icon: Icon(_arme ? Icons.cancel : Icons.close, color: _arme ? Colors.red.shade700 : Pal.muted),
                )
              else if (client == null)
                const Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.search, size: 20, color: Pal.muted))
              else
                const SizedBox(width: 10),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Page « Client de la vente » : recherche, résultats, « Nouveau client ». Renvoie true si un client a été associé.
class ClientVentePage extends StatefulWidget {
  final VenteController controller;

  /// Anti-rebond de la recherche (frappe rapide → une seule requête).
  final Duration antiRebond;
  const ClientVentePage({super.key, required this.controller, this.antiRebond = const Duration(milliseconds: 350)});

  @override
  State<ClientVentePage> createState() => _ClientVentePageState();
}

class _ClientVentePageState extends State<ClientVentePage> {
  final _recherche = TextEditingController();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _telephone = TextEditingController();
  Timer? _rebond;
  int _numero = 0;
  bool _cherche = false;
  bool _occupe = false;
  bool _nouveau = false;
  String? _erreur;
  List<ClientVente>? _resultats;

  /// Client créé mais pas encore associé (association refusée) : on l'associe sans le recréer.
  ClientVente? _cree;

  VenteController get _c => widget.controller;

  @override
  void dispose() {
    _rebond?.cancel();
    _recherche.dispose();
    _nom.dispose();
    _prenom.dispose();
    _telephone.dispose();
    super.dispose();
  }

  void _surFrappe(String _) {
    _rebond?.cancel();
    final texte = _recherche.text;
    if (!rechercheClientPossible(texte)) {
      _numero++;
      setState(() {
        _cherche = false;
        _resultats = null;
        _erreur = null;
      });
      return;
    }
    _rebond = Timer(widget.antiRebond, () => _chercher(texte));
  }

  Future<void> _chercher(String texte, {bool garderErreur = false}) async {
    final n = ++_numero;
    setState(() {
      _cherche = true;
      if (!garderErreur) _erreur = null;
    });
    final r = await _c.rechercherClients(texte);
    if (!mounted || n != _numero) return; // réponse d'une frappe précédente
    setState(() {
      _cherche = false;
      if (r case VenteOk(:final value)) {
        _resultats = value;
        if (!garderErreur) _erreur = null;
      } else {
        _resultats = null;
        _erreur = venteMessage(r.message);
      }
    });
  }

  Future<void> _choisir(ClientVente c) async {
    if (_occupe) return;
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await _c.choisirClient(c);
    if (!mounted) return;
    if (r.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _occupe = false;
      _erreur = venteMessage(r.message);
    });
  }

  Future<void> _creer() async {
    if (_occupe) return;
    final cree = _cree;
    if (cree != null) return _choisir(cree);
    setState(() {
      _occupe = true;
      _erreur = null;
    });
    final r = await _c.creerClient(nom: _nom.text, prenom: _prenom.text, telephone: _telephone.text);
    if (!mounted) return;
    if (r case VenteOk(:final value)) {
      setState(() => _cree = value);
      final a = await _c.choisirClient(value);
      if (!mounted) return;
      if (a.isOk) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _occupe = false;
        _erreur = 'Client créé, mais non associé à la vente : ${venteMessage(a.message)}';
      });
      return;
    }
    setState(() {
      _occupe = false;
      _erreur = venteMessage(r.message);
      // Création peut-être faite (réponse perdue) : chercher le client avant de le recréer.
      if (r.uncertain) {
        _nouveau = false;
        _recherche.text = _nom.text.trim();
      }
    });
    if (r.uncertain && rechercheClientPossible(_recherche.text)) await _chercher(_recherche.text, garderErreur: true);
  }

  Widget _champ(String cle, TextEditingController ctl, String libelle,
          {TextInputType? clavier, TextCapitalization casse = TextCapitalization.characters, List<TextInputFormatter>? formats}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          key: ValueKey(cle),
          controller: ctl,
          enabled: !_occupe && _cree == null,
          keyboardType: clavier,
          textCapitalization: casse,
          inputFormatters: [LengthLimitingTextInputFormatter(50), ...?formats],
          decoration: InputDecoration(labelText: libelle, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  /// Texte des boutons : police du thème (comme le reste de la page), gras 15.
  static TextStyle _texteBouton(BuildContext context) =>
      (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600, fontSize: 15);

  Widget _formulaire() {
    final cree = _cree;
    return Container(
      key: const ValueKey('client-vente-formulaire'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Nouveau client', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Pal.ink)),
        _champ('client-vente-nom-saisi', _nom, 'Nom'),
        _champ('client-vente-prenom-saisi', _prenom, 'Prénom', casse: TextCapitalization.words),
        _champ('client-vente-telephone-saisi', _telephone, 'Téléphone',
            clavier: TextInputType.phone, casse: TextCapitalization.none, formats: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +.\-]'))]),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          key: const ValueKey('client-vente-creer'),
          style: navyButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48)), textStyle: WidgetStatePropertyAll(_texteBouton(context))),
          onPressed: _occupe ? null : _creer,
          icon: Icon(cree == null ? Icons.person_add_alt_1 : Icons.link, size: 20),
          label: FittedBox(fit: BoxFit.scaleDown, child: Text(cree == null ? 'Créer et associer à la vente' : 'Associer le client créé')),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultats = _resultats;
    final texte = _recherche.text.trim();
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(
        title: const Text('Client de la vente'),
        backgroundColor: Pal.navy,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('client-vente-page'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            TextField(
              key: const ValueKey('client-vente-recherche'),
              controller: _recherche,
              autofocus: true,
              enabled: !_occupe,
              textInputAction: TextInputAction.search,
              onChanged: _surFrappe,
              onSubmitted: (t) {
                _rebond?.cancel();
                if (rechercheClientPossible(t)) _chercher(t);
              },
              decoration: InputDecoration(
                labelText: 'Nom, prénom ou numéro',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                suffixIcon: _cherche ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
            ),
            if (texte.isNotEmpty && !rechercheClientPossible(texte))
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(VenteController.messageClientRecherche, key: ValueKey('client-vente-aide'), style: TextStyle(fontSize: 12, color: Pal.muted)),
              ),
            if (_erreur != null)
              Container(
                key: const ValueKey('client-vente-erreur'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(10)),
                child: Text(_erreur!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
              ),
            if (_occupe) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
            if (resultats != null && !_nouveau) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(resultats.isEmpty ? 'Aucun client trouvé.' : '${resultats.length} client${resultats.length > 1 ? 's' : ''}',
                    key: const ValueKey('client-vente-nombre'), style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
              ),
              for (final c in resultats)
                Card(
                  margin: const EdgeInsets.only(top: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.line)),
                  elevation: 0,
                  child: ListTile(
                    key: ValueKey('client-vente-resultat-${c.id}'),
                    enabled: !_occupe,
                    minVerticalPadding: 8,
                    leading: const Icon(Icons.person_outline, color: Pal.navy),
                    title: Text(c.nomComplet, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: c.telephone.isEmpty ? null : Text(c.telephone, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => _choisir(c),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            if (!_nouveau)
              OutlinedButton.icon(
                key: const ValueKey('client-vente-nouveau'),
                style: outlineButton.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48)), textStyle: WidgetStatePropertyAll(_texteBouton(context))),
                onPressed: _occupe
                    ? null
                    : () => setState(() {
                          _nouveau = true;
                          _erreur = null;
                          // Le texte cherché devient le nom proposé (s'il n'est pas un numéro).
                          if (_nom.text.isEmpty && texte.isNotEmpty && !RegExp(r'^[\d\s+.\-]+$').hasMatch(texte)) _nom.text = texte.toUpperCase();
                        }),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Nouveau client'),
              )
            else
              _formulaire(),
          ],
        ),
      ),
    );
  }
}
