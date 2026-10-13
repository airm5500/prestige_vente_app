// lib/reserve/reserve_regles.dart
// Règles pures du menu « Réserve » (testées sans serveur) : saisie des quantités, choix d'une suggestion
// existante à reprendre plutôt que d'en créer une nouvelle, résumé du compte rendu.
import 'package:prestige_vente_app/reserve/reserve_models.dart';

/// Quantité maximale acceptée sur une ligne (garde-fou contre une saisie aberrante).
const int quantiteMaxLigne = 99999;

/// Lit une quantité saisie : entier strictement positif, chiffres seulement (pas de signe, de virgule ni d'espace
/// au milieu). Null si la saisie n'est pas un entier positif.
int? lireQuantite(String saisie) {
  final s = saisie.trim();
  if (!RegExp(r'^\d{1,9}$').hasMatch(s)) return null;
  final v = int.tryParse(s);
  return v == null || v <= 0 ? null : v;
}

/// Contrôle d'une quantité à déplacer : null si elle est valable, sinon le message à afficher.
/// [disponible] : stock côté SOURCE (rayon pour Rayon → Réserve, réserve pour Réserve → Rayon).
String? validerQuantite(String saisie, {required int disponible, required SensReserve sens}) {
  final s = saisie.trim();
  if (s.isEmpty) return 'Saisissez une quantité.';
  if (!RegExp(r'^\d+$').hasMatch(s)) return 'Saisissez un nombre entier de boîtes (sans virgule ni signe).';
  final v = lireQuantite(s);
  if (v == null) return 'La quantité doit être supérieure à 0.';
  if (v > quantiteMaxLigne) return 'Quantité trop grande ($quantiteMaxLigne au plus).';
  if (disponible <= 0) return 'Le stock ${sens.source} est vide : rien à déplacer.';
  if (v > disponible) return 'Le stock ${sens.source} n\'en contient que $disponible.';
  return null;
}

/// Quantité proposée par défaut pour un article ajouté au panier : la suggestion du serveur si elle est
/// valable et ne dépasse pas le stock source, sinon rien (le préparateur saisit).
int? quantiteParDefaut(ArticleReserve a, SensReserve sens) {
  final q = a.qteSuggeree;
  if (q == null || q <= 0) return null;
  final dispo = a.disponible(sens);
  if (dispo <= 0) return null;
  return q > dispo ? dispo : q;
}

/// Suggestions encore à traiter du même sens et de la même origine (la plus récente d'abord, comme le serveur) :
/// le préparateur les reprend au lieu d'en recréer une (la création n'est pas idempotente côté serveur).
List<EnteteSuggestion> suggestionsAReprendre(Iterable<EnteteSuggestion> enAttente, SensReserve sens, OrigineSuggestion origine) =>
    [for (final s in enAttente) if (s.ouverte && s.sens == sens && s.origine == origine && s.id.isNotEmpty) s];

/// Ajoute (ou remplace) un article dans le panier : un même produit n'apparaît qu'une fois
/// (le serveur ignorerait le doublon).
List<LignePanier> ajouterAuPanier(List<LignePanier> panier, ArticleReserve a, int quantite) {
  final out = [for (final l in panier) if (l.article.familleId != a.familleId) l];
  final i = panier.indexWhere((l) => l.article.familleId == a.familleId);
  if (i < 0) {
    out.add(LignePanier(a, quantite));
  } else {
    out.insert(i, LignePanier(a, quantite));
  }
  return out;
}

/// Corps de POST v1/suggestion-reserve/creer.
Map<String, dynamic> corpsCreation(SensReserve sens, int motifId, String commentaire, List<LignePanier> panier) => {
      'categorie': sens.categorieApi,
      'motifId': motifId,
      'commentaire': commentaire.trim().isEmpty ? null : commentaire.trim(),
      'items': [
        for (final l in panier) {'lg_FAMILLE_ID': l.article.familleId, 'int_QTE': l.quantite},
      ],
    };

/// Résumé avant traitement : nombre de lignes et de boîtes qui seront réellement déplacées.
({int lignes, int boites}) resumeTraitement(Iterable<LigneSuggestion> lignes) {
  var n = 0, b = 0;
  for (final l in lignes) {
    if (l.traitable) {
      n++;
      b += l.qteATraiter;
    }
  }
  return (lignes: n, boites: b);
}

/// Lignes qui dépassent le stock source actuel (le traitement les refuserait) : à signaler avant de traiter.
List<LigneSuggestion> lignesAuDelaDuStock(Iterable<LigneSuggestion> lignes, SensReserve sens) =>
    [for (final l in lignes) if (l.traitable && l.qteATraiter > l.disponible(sens)) l];

/// Libellé d'un code d'échec du serveur (ReserveService), en langage courant.
String libelleCodeEchec(String code, SensReserve sens) => switch (code) {
      'STOCK_RAYON_INSUFFISANT' => 'Stock rayon insuffisant',
      'STOCK_RESERVE_INSUFFISANT' => 'Stock réserve insuffisant',
      'CONFIG_STOCK_INCOMPLETE' => 'Produit non configuré en réserve',
      'ARTICLE_INTROUVABLE' => 'Produit introuvable',
      'QUANTITE_INVALIDE' => 'Quantité invalide',
      'CONFLIT_CONCURRENCE' => 'Stock modifié en même temps par un autre poste : réessayez',
      'ERREUR_TECHNIQUE' => 'Erreur technique du serveur',
      'SUGGESTION_OCCUPEE' => 'Suggestion ouverte par un autre utilisateur',
      _ => code,
    };

/// Raison affichée pour une ligne non traitée du compte rendu.
String raisonNonTraitee(LigneSuggestion l, SensReserve sens) {
  if (l.raison.isNotEmpty) return l.raison;
  if (l.motifLigne.isNotEmpty) return l.motifLigne;
  if (l.codeEchec.isNotEmpty) return libelleCodeEchec(l.codeEchec, sens);
  return EtatLigne.libelle(l.etat);
}

/// Phrase de synthèse du compte rendu.
String syntheseCompteRendu(CompteRendu c) {
  final sens = c.entete.sens;
  final parts = <String>[
    '${c.totalReussi} ligne(s) déplacée(s) (${c.boitesDeplacees} boîte(s), ${sens.fleche})',
    if (c.totalEchoue > 0) '${c.totalEchoue} refusée(s)',
    if (c.totalIgnore > 0) '${c.totalIgnore} non traitée(s)',
    if (c.totalSupprime > 0) '${c.totalSupprime} retirée(s)',
  ];
  return parts.join(' · ');
}
