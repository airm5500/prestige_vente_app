// lib/ventes/common/remise_vente.dart
// 4.14.0 — REMISE sur les ventes comptant, assurance et carnet (demande du pharmacien du 19/11/2026 : « ajouter remise
// sur les ventes (comptant, assurance, carnet) », sans régression).
//
// Contrat du serveur (lu le 19/11 sur integration/recette-2026-10-29, f0282bf0), le même que le poste web :
//  - liste : GET v1/common/remises-client → {success, data:[{lgREMISEID, strNAME, strCODE, …}], la dernière
//    {lgREMISEID:null, "SANS REMISE"}} : la liste « REMISE » de l'écran de vente du web (VenteVNO.js) ;
//  - appliquer / retirer : POST v1/vente/remise {venteId, remiseId} (remiseId null = retirer)
//    → {success:true|false, msg} (RemiseServiceImpl.addRemise : pose la remise, efface les montants de l'ancienne) ;
//  - montants relus sur le serveur, jamais calculés ici :
//      comptant : POST v1/vente/net/vno {venteId, remiseId, checkUg:false}. ATTENTION (audit VC-06 du serveur) : sans
//      `remiseId`, net/vno remet la remise de la vente à 0 ; chaque calcul du net envoie donc la remise choisie ;
//      assurance / carnet : POST v1/vente/net/assurance (le serveur lit la remise de la vente, à défaut celle de la
//      fiche du client : remise automatique du client) ; la remise porte sur la part du client (assurance) ou sur
//      le montant (carnet), jamais sur la part des organismes ;
//  - grille : la remise d'une ligne dépend du code remise du produit (grille VNO ou VO) ; produit non remisable ou
//    en promotion : aucune remise ;
//  - droit : AUCUN droit dédié côté serveur (la route n'est contrôlée que par la session). 4.15.0 (décision du
//    pharmacien du 19/11) : proposée à TOUT compte qui a un écran de vente, comptes de prévente compris, comme le web ;
//    le serveur reste juge : un 403 `interdit` la masque pour la session. La borne ne propose jamais de remise ;
//  - hors ligne : aucune route ; la remise n'est pas proposée hors ligne (elle n'est appliquée qu'après la réponse
//    du serveur).
//
// 4.15.1 — Réponse du serveur à la demande 63 (correctif/demande63-1911, bb6b4604, vérifiée dans le code, PAS encore
// fusionnée ; le serveur de l'officine ne l'a pas) :
//  - droit P_REMISE_VENTE « Remise sur une vente » : POST v1/vente/remise (et v2) → 403 {interdit:true, msg:"Droit
//    manquant : Remise sur une vente"} sans lui ; listé par GET v1/user/droits ; la migration le donne à TOUS les
//    rôles existants, le pharmacien le retire ensuite par rôle. Règle de l'application (remiseAutorisee) : droits
//    connus ET serveur qui connaît le droit → remise seulement aux comptes qui l'ont. « Serveur qui connaît le droit »
//    n'est jamais déduit de son absence (un serveur ancien ne le donne à personne) ; il est prouvé par : le droit
//    présent dans la liste d'un compte de ce serveur, un 403 `interdit` sur la remise, une réponse JSON de la route
//    image du ticket (route de la même branche), ou `data` dans la réponse de vente/remise d'une vente comptant.
//    Sans preuve : règle de 4.15.0 (tout compte qui a un écran de vente ; un 403 la masque pour la session) ;
//  - « sans remise » : vente/remise {remiseId:"0"} retire la remise de CETTE vente, y compris celle de la fiche du
//    client (assurance / carnet : net, clôture, base) ; remiseId null ou vide garde l'ancien sens (la fiche
//    s'applique). « Retirer » et « SANS REMISE » envoient "0" seulement quand le serveur est prouvé (ci-dessus) ;
//    sinon null, comme en 4.15.0 : sur l'intégration d'aujourd'hui (f0282bf0), "0" serait écrit tel quel dans
//    lg_REMISE_ID sans retirer la remise de la fiche (RemiseServiceImpl.addRemise, calcul du net inchangé) ;
//  - réponse : remise inconnue, vente terminée, annulée ou inconnue → {success:false, msg} (vente non touchée) :
//    message affiché tel quel, remise non affichée ; comptant : `data` = net recalculé (celui de net/vno) → pas de
//    second appel à net/vno ; sans `data` (serveur ancien, assurance / carnet) : net relu comme avant.
// Aucun nom de client ni texte saisi n'est écrit dans un journal.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Une remise de la liste du serveur.
class RemiseOption {
  final String id;
  final String nom;
  final String code;
  const RemiseOption({required this.id, required this.nom, this.code = ''});

  /// 4.15.1 : « SANS REMISE » de la liste du serveur, proposé seulement quand le serveur connaît "0".
  static const RemiseOption sansRemise = RemiseOption(id: idSansRemise, nom: 'SANS REMISE');

  static RemiseOption? depuisJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['lgREMISEID'] ?? ''}'.trim();
    if (id.isEmpty || id == 'null') return null; // « SANS REMISE » : c'est « Retirer la remise »
    final nom = '${j['strNAME'] ?? j['libelle'] ?? ''}'.trim();
    return RemiseOption(id: id, nom: nom.isEmpty ? 'Remise' : nom, code: '${j['strCODE'] ?? ''}'.trim());
  }

  @override
  bool operator ==(Object other) => other is RemiseOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Routes de la remise. Interface à part : une passerelle qui ne l'implémente pas n'affiche pas la zone Remise.
abstract class RemiseVenteGateway {
  /// GET v1/common/remises-client (sans « SANS REMISE »).
  Future<VenteResult<List<RemiseOption>>> remisesVente();

  /// POST v1/vente/remise {venteId, remiseId} ; [remiseId] null = retirer. Succès seulement sur `success:true`.
  Future<VenteResult<void>> appliquerRemise(String venteId, String? remiseId);

  /// POST v1/vente/net/vno avec la remise choisie (comptant) ; [remiseId] null = sans remise.
  Future<VenteResult<SaleSummary>> netVnoRemise(String venteId, String? remiseId);
}

/// 4.15.1 : POST v1/vente/remise qui rend aussi le net d'une vente comptant (`data`, demande 63 point 5) ; null :
/// réponse sans `data` (serveur ancien, assurance / carnet). Interface à part (passerelles de test inchangées).
abstract class RemiseVenteNetGateway {
  Future<VenteResult<SaleSummary?>> appliquerRemiseNet(String venteId, String? remiseId);
}

/// Droit dédié (demande 63, serveur correctif/demande63-1911). Absent de GET v1/user/droits sur un serveur ancien.
const String droitRemiseVente = DroitsVente.remiseVenteDroit;

/// 4.15.1 : identifiant « sans remise » de vente/remise (demande 63, point 3).
const String idSansRemise = '0';

/// La remise peut être proposée à ce compte.
///  - droit P_REMISE_VENTE dans la liste : oui ;
///  - droits connus et serveur qui contrôle le droit (demande 63 prouvée) : non (le pharmacien l'a retiré au rôle) ;
///  - sinon, règle de 4.15.0 (décision du pharmacien du 19/11) : à tout compte qui a un écran de vente, prévente
///    comprise, comme le web ; jamais si le serveur l'a refusée (403 `interdit`) à ce compte pendant la session.
bool remiseAutorisee(DroitsVente d) {
  if (d.droits.contains(droitRemiseVente)) return true;
  if (d.connus) return !d.controle(droitRemiseVente);
  return !d.refuse(droitRemiseVente);
}

/// 4.15.1 : le serveur connaît « sans remise » = "0" (demande 63 prouvée, voir l'en-tête).
bool sansRemiseParZero(DroitsVente d) => d.controle(droitRemiseVente);

/// 4.15.1 : remiseId envoyé à vente/remise pour [r] (null = retirer la remise choisie) : "0" pour « sans remise » sur
/// un serveur qui le connaît, null sinon (sens d'avant : la fiche du client s'applique).
String? remiseIdEnvoye(RemiseOption? r, DroitsVente d) {
  if (r != null && r.id != idSansRemise) return r.id;
  return sansRemiseParZero(d) ? idSansRemise : null;
}

/// 4.15.1 : remise gardée sur la vente après succès ("0" ou null : aucune remise choisie).
String? remiseIdRetenue(String? envoye) => envoye == null || envoye == idSansRemise ? null : envoye;

/// 4.15.1 : remise relue (lgREMISEID de ventestats/{id}) après une réponse perdue = remise envoyée. « Sans remise »
/// ("0") se relit vide : ventestats lit l'identifiant de la remise de la vente (aucune), pas la colonne brute.
bool remiseRelueEgale(Object? lu, String? envoye) {
  String n(Object? v) {
    final t = '${v ?? ''}'.trim();
    return t == 'null' || t == idSansRemise ? '' : t;
  }

  return n(lu) == n(envoye);
}

/// 403 `interdit` reçu sur la remise : masquée pour la session (le serveur la contrôle).
void remiseRefuseeParServeur() => DroitsVente.instance.refusConstate(droitRemiseVente);

/// État de la remise d'une vente, partagé par les trois contrôleurs.
class RemiseVenteEtat {
  /// Remise posée sur la vente (confirmée par le serveur), ou null.
  String? id;

  /// Nom affiché (null tant que la liste n'est pas lue pour une remise relue avec la vente).
  String? nom;

  List<RemiseOption>? _liste;

  void vider() {
    id = null;
    nom = null;
  }

  /// Liste du serveur (lue une fois par vente / écran).
  Future<VenteResult<List<RemiseOption>>> liste(RemiseVenteGateway g) async {
    final l = _liste;
    if (l != null) return VenteOk(l);
    final r = await g.remisesVente();
    if (r case VenteOk(:final value)) {
      _liste = value;
      if (id != null && nom == null) nom = value.where((o) => o.id == id).firstOrNull?.nom;
    }
    return r;
  }
}

/// Ce que l'écran demande à un contrôleur de vente pour la remise.
abstract class RemiseVenteHote implements Listenable {
  /// Zone visible (passerelle capable, vente créée, en ligne, droit, pas terminée).
  bool get remiseDisponible;

  /// Remise posée (null : aucune).
  String? get remiseId;
  String? get remiseNom;

  /// Montant de la remise lu sur le serveur (0 si aucune ou net pas à jour).
  int get montantRemise;

  bool get busy;

  Future<VenteResult<List<RemiseOption>>> remisesProposees();
  Future<VenteResult<void>> choisirRemise(RemiseOption r);
  Future<VenteResult<void>> retirerRemise();
}

/// Zone « Remise » de l'écran de vente : « Remise : aucune » [Choisir] ; ou « REMISE X · − 500 F » [Changer] [×].
class RemiseVenteZone extends StatelessWidget {
  final RemiseVenteHote hote;
  final bool enabled;
  const RemiseVenteZone({super.key, required this.hote, this.enabled = true});

  Future<void> _choisir(BuildContext context) async {
    final liste = await hote.remisesProposees();
    if (!context.mounted) return;
    if (liste is! VenteOk<List<RemiseOption>>) {
      showVenteFailure(context, liste);
      return;
    }
    // 4.15.1 : « SANS REMISE » (retire aussi la remise de la fiche du client) quand le serveur connaît "0".
    final options = [...liste.value, if (sansRemiseParZero(DroitsVente.instance)) RemiseOption.sansRemise];
    if (options.isEmpty) {
      showVenteSnack(context, 'Aucune remise n\'est définie sur le serveur.');
      return;
    }
    final choisie = await showModalBottomSheet<RemiseOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Choisir une remise', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Pal.ink)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Mêmes remises que le poste. Le montant est calculé par le serveur selon les produits.',
                  style: TextStyle(fontSize: 12.5, color: Pal.muted)),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final o in options)
                  ListTile(
                    key: ValueKey('remise-option-${o.id}'),
                    minTileHeight: 52,
                    leading: Icon(o.id == hote.remiseId ? Icons.radio_button_checked : Icons.radio_button_off, color: Pal.navy),
                    title: Text(o.nom, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(ctx).pop(o),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (choisie == null || !context.mounted) return;
    final r = await hote.choisirRemise(choisie);
    if (!context.mounted) return;
    if (r.isOk) {
      showVenteSnack(context, choisie.id == idSansRemise ? 'Sans remise pour cette vente.' : 'Remise appliquée : ${choisie.nom}.',
          color: Colors.green.shade700);
    } else {
      showVenteFailure(context, r);
    }
  }

  Future<void> _retirer(BuildContext context) async {
    final r = await hote.retirerRemise();
    if (!context.mounted) return;
    if (r.isOk) {
      showVenteSnack(context, hote.montantRemise > 0
          ? 'Remise retirée de la vente. Le serveur applique la remise de la fiche du client.'
          : 'Remise retirée de la vente.');
    } else {
      showVenteFailure(context, r);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: hote,
        builder: (context, _) {
          final actif = enabled && hote.remiseDisponible && !hote.busy;
          final id = hote.remiseId;
          final montant = hote.montantRemise;
          final titre = id != null ? (hote.remiseNom ?? 'Remise appliquée') : (montant > 0 ? 'Remise du client' : 'Remise');
          final detail = montant > 0
              ? '− ${Constants.formatNumber(montant)} F (calcul du serveur)'
              : (id != null ? 'Aucun produit remisable pour l\'instant' : 'Aucune remise');
          return Container(
            key: const ValueKey('remise-vente-zone'),
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('remise-vente-choisir'),
                borderRadius: BorderRadius.circular(12),
                onTap: actif ? () => _choisir(context) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    const SizedBox(width: 10),
                    Icon(Icons.percent, size: 22, color: id != null || montant > 0 ? Pal.navy : Pal.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(titre,
                              key: const ValueKey('remise-vente-nom'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: id != null ? FontWeight.bold : FontWeight.w600, fontSize: 14, color: id != null ? Pal.ink : Pal.navy)),
                          Text(detail,
                              key: const ValueKey('remise-vente-montant'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Pal.muted)),
                        ]),
                      ),
                    ),
                    if (hote.busy)
                      const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                    if (id != null)
                      IconButton(
                        key: const ValueKey('remise-vente-retirer'),
                        tooltip: 'Retirer la remise',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: actif ? () => _retirer(context) : null,
                        icon: const Icon(Icons.close, color: Pal.muted),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text('Choisir', style: TextStyle(fontWeight: FontWeight.w600, color: actif ? Pal.navy : Pal.muted)),
                      ),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// Remise des ventes ASSURANCE et CARNET : le net (POST v1/vente/net/assurance) lit la remise posée sur la vente, à
/// défaut celle de la fiche du client ; aucun paramètre à ajouter au calcul du net.
mixin RemiseVenteVoMixin on ChangeNotifier implements RemiseVenteHote {
  final RemiseVenteEtat remiseEtat = RemiseVenteEtat();

  /// Passerelle de la vente (champ du contrôleur).
  Object get passerelleRemise;

  /// Vente créée sur le serveur (null : pas encore).
  String? get venteIdRemise;

  /// Vente saisie hors ligne ou serveur hors ligne.
  bool get remiseHorsLigne;

  bool get remiseTerminee;

  /// Numéro de la vente en cours (change à chaque nouvelle vente).
  int get remiseEpoch;

  /// Remise du dernier net calculé (0 si net pas à jour).
  int get remiseDuNet;

  /// Exécute dans la file des opérations de la vente.
  Future<T> remiseDansLaFile<T>(Future<T> Function() op);

  /// Après une remise confirmée : modification notée, panier et net relus, vente mémorisée.
  Future<void> apresRemise();

  /// Relecture de la vente (lgREMISEID) : GET ventestats/{id}.
  Future<VenteResult<Map<String, dynamic>>> relireVentePourRemise(String id);

  RemiseVenteGateway? get _g => passerelleRemise is RemiseVenteGateway ? passerelleRemise as RemiseVenteGateway : null;

  /// Remise lue avec la vente reprise (champ lgREMISEID de ventestats/{id}).
  void lireRemiseDe(Map<String, dynamic> vente) {
    final id = '${vente['lgREMISEID'] ?? ''}'.trim();
    remiseEtat.id = id.isEmpty || id == 'null' || id == '0' ? null : id;
    remiseEtat.nom = null;
  }

  @override
  bool get remiseDisponible =>
      _g != null && venteIdRemise != null && !remiseHorsLigne && !remiseTerminee && remiseAutorisee(DroitsVente.instance);

  @override
  String? get remiseId => remiseEtat.id;

  @override
  String? get remiseNom => remiseEtat.nom;

  @override
  int get montantRemise => remiseDuNet;

  @override
  Future<VenteResult<List<RemiseOption>>> remisesProposees() async {
    final g = _g;
    if (g == null) return const VenteRefused('Remise indisponible.');
    if (remiseHorsLigne) return const VenteRefused('Serveur hors ligne : la remise se choisit en ligne.');
    return remiseEtat.liste(g);
  }

  @override
  Future<VenteResult<void>> choisirRemise(RemiseOption r) => _poser(r);

  @override
  Future<VenteResult<void>> retirerRemise() => _poser(null);

  Future<VenteResult<void>> _poser(RemiseOption? r) => remiseDansLaFile(() async {
        final g = _g;
        final id = venteIdRemise;
        if (g == null || id == null) return const VenteRefused('Aucune vente en cours : ajoutez d\'abord un article.');
        if (remiseHorsLigne) return const VenteRefused('Serveur hors ligne : la remise se choisit en ligne.');
        if (remiseTerminee) return const VenteRefused('Vente déjà terminée.');
        if (!remiseAutorisee(DroitsVente.instance)) return const VenteRefused('Remise réservée aux comptes autorisés.', code: VenteRefused.codeInterdit);
        final epoch = remiseEpoch;
        final envoye = remiseIdEnvoye(r, DroitsVente.instance);
        var res = await g.appliquerRemise(id, envoye);
        if (epoch != remiseEpoch || id != venteIdRemise) return const VenteRefused('Vente changée : remise non appliquée.');
        if (res is VenteRefused<void> && res.interdit) {
          remiseRefuseeParServeur();
          return res;
        }
        if (res.uncertain) {
          final v = await relireVentePourRemise(id);
          if (v case VenteOk(:final value)) {
            if (remiseRelueEgale(value['lgREMISEID'], envoye)) res = const VenteOk(null);
          }
        }
        if (!res.isOk) return res;
        remiseEtat.id = remiseIdRetenue(envoye);
        remiseEtat.nom = remiseEtat.id == null ? null : r?.nom;
        await apresRemise();
        return const VenteOk(null);
      });
}
