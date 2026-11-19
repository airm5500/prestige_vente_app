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
//  - droit : AUCUN droit dédié côté serveur (la route n'est contrôlée que par la session). Repli prudent : la remise
//    est proposée aux comptes qui peuvent terminer une vente (droits de DroitsVente.terminerVente) ou au droit
//    « P_REMISE_VENTE » s'il apparaît dans GET v1/user/droits (demande 63) ; un 403 `interdit` la masque pour la
//    session ;
//  - hors ligne : aucune route ; la remise n'est pas proposée hors ligne (elle n'est appliquée qu'après la réponse
//    du serveur).
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

/// Droit dédié demandé au serveur (demande 63). Absent de GET v1/user/droits aujourd'hui.
const String droitRemiseVente = 'P_REMISE_VENTE';

/// La remise peut être proposée à ce compte : droit dédié, sinon (repli) le droit de terminer une vente ; jamais si le
/// serveur l'a refusée (403) pendant la session.
bool remiseAutorisee(DroitsVente d) {
  if (d.droits.contains(droitRemiseVente)) return true;
  if (d.connus && !d.terminerVente) return false;
  return !d.controle(droitRemiseVente);
}

/// 403 `interdit` reçu sur la remise : masquée pour la session (le serveur la contrôle).
void remiseRefuseeParServeur() => DroitsVente.instance.controleConstate(droitRemiseVente);

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
    if (liste.value.isEmpty) {
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
                for (final o in liste.value)
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
      showVenteSnack(context, 'Remise appliquée : ${choisie.nom}.', color: Colors.green.shade700);
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
        var res = await g.appliquerRemise(id, r?.id);
        if (epoch != remiseEpoch || id != venteIdRemise) return const VenteRefused('Vente changée : remise non appliquée.');
        if (res is VenteRefused<void> && res.interdit) {
          remiseRefuseeParServeur();
          return res;
        }
        if (res.uncertain) {
          final v = await relireVentePourRemise(id);
          if (v case VenteOk(:final value)) {
            final lu = '${value['lgREMISEID'] ?? ''}'.trim();
            if ((lu == 'null' ? '' : lu) == (r?.id ?? '')) res = const VenteOk(null);
          }
        }
        if (!res.isOk) return res;
        remiseEtat.id = r?.id;
        remiseEtat.nom = r?.nom;
        await apresRemise();
        return const VenteOk(null);
      });
}
