// lib/reserve/reserve_models.dart
// Modèles du menu « Réserve » (routes v1/reserve et v1/suggestion-reserve de Prestige).
//
// ATTENTION au vocabulaire du serveur, inversé par rapport à l'intuition :
//   catégorie RESERVE = « réappro réserve »  = RAYON → RÉSERVE (on range le surplus du rayon en réserve) ;
//   catégorie RAYON   = « réappro rayon »    = RÉSERVE → RAYON (on regarnit le rayon depuis la réserve).
// L'application n'affiche jamais « RESERVE » / « RAYON » seuls : toujours le sens physique (« Rayon → Réserve »).
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

/// Sens physique d'un réappro.
enum SensReserve {
  /// Catégorie serveur RESERVE : rayon → réserve.
  versReserve,

  /// Catégorie serveur RAYON : réserve → rayon.
  versRayon;

  /// Valeur `categorie` attendue par le serveur.
  String get categorieApi => this == versReserve ? 'RESERVE' : 'RAYON';

  /// Lecture d'une catégorie serveur : comme le serveur (normaliserCategorie), tout ce qui n'est pas RESERVE est RAYON.
  static SensReserve depuisCategorie(Object? categorie) => txt(categorie).toUpperCase() == 'RESERVE' ? versReserve : versRayon;

  /// Sens affiché partout.
  String get fleche => this == versReserve ? 'Rayon → Réserve' : 'Réserve → Rayon';

  /// Ce que fait le préparateur.
  String get action => this == versReserve ? 'Ranger le surplus du rayon en réserve' : 'Regarnir le rayon depuis la réserve';

  /// Nom de l'opération dans Prestige (pour faire le lien avec l'écran web).
  String get nomPrestige => this == versReserve ? 'Réappro RÉSERVE' : 'Réappro RAYON';

  /// D'où sortent les boîtes.
  String get source => this == versReserve ? 'rayon' : 'réserve';

  /// Où vont les boîtes.
  String get destination => this == versReserve ? 'réserve' : 'rayon';
}

/// Origine d'une suggestion.
enum OrigineSuggestion {
  manuelle,
  automatique,
  autre;

  static OrigineSuggestion lire(Object? v) => switch (txt(v).toUpperCase()) {
        'MANUELLE' => manuelle,
        'AUTOMATIQUE' => automatique,
        _ => autre,
      };

  String get libelle => switch (this) {
        manuelle => 'Manuelle',
        automatique => 'Automatique',
        autre => 'Système',
      };
}

/// Produit suivi en réserve (GET v1/reserve/articles).
class ArticleReserve {
  final String familleId;
  final String cip;
  final String nom;
  final String zone;
  final int stockRayon;
  final int stockReserve;
  final int? seuilReserve;
  final int? seuilMiniRayon;
  final int? qteSuggeree;

  const ArticleReserve({
    required this.familleId,
    required this.cip,
    required this.nom,
    this.zone = '',
    required this.stockRayon,
    required this.stockReserve,
    this.seuilReserve,
    this.seuilMiniRayon,
    this.qteSuggeree,
  });

  factory ArticleReserve.fromJson(Map<String, dynamic> j) => ArticleReserve(
        familleId: txt(j['lg_FAMILLE_ID']),
        cip: txt(j['int_CIP']),
        nom: txtOuNull(j['str_NAME']) ?? txt(j['str_DESCRIPTION']),
        zone: txt(j['lg_ZONE_GEO_ID']),
        stockRayon: entier0(j['int_STOCK_RAYON']),
        stockReserve: entier0(j['int_STOCK_RESERVE']),
        seuilReserve: entier(j['int_SEUIL_RESERVE']),
        seuilMiniRayon: entier(j['int_SEUIL_MINI_RAYON']),
        qteSuggeree: entier(j['int_QTE_SUGGEREE']),
      );

  /// Stock d'où partent les boîtes.
  int disponible(SensReserve sens) => sens == SensReserve.versReserve ? stockRayon : stockReserve;
}

/// Page d'articles (`{total, results}`).
class PageArticles {
  final List<ArticleReserve> articles;
  final int total;
  const PageArticles(this.articles, this.total);

  factory PageArticles.fromJson(Map<String, dynamic> j) {
    final l = [for (final o in objets(j['results'] ?? j['data'])) ArticleReserve.fromJson(o)]..removeWhere((a) => a.familleId.isEmpty);
    return PageArticles(l, entier(j['total']) ?? l.length);
  }
}

/// Motif d'une suggestion (obligatoire à la création).
class MotifReserve {
  final int id;
  final String libelle;
  final String categorie;
  const MotifReserve({required this.id, required this.libelle, this.categorie = ''});

  static MotifReserve? fromJson(Map<String, dynamic> j) {
    final id = entier(j['id']);
    if (id == null) return null;
    return MotifReserve(id: id, libelle: txtOuNull(j['libelle']) ?? 'Motif $id', categorie: txt(j['categorie']));
  }
}

/// Statuts d'une suggestion.
class StatutSuggestion {
  StatutSuggestion._();
  static const aTraiter = 'A_TRAITER';
  static const enCours = 'EN_COURS';
  static const traitee = 'TRAITEE';
  static const supprimee = 'SUPPRIMEE';
  static const annulee = 'ANNULEE';

  static String libelle(String s) => switch (s) {
        aTraiter => 'À traiter',
        enCours => 'En cours',
        traitee => 'Traitée',
        supprimee => 'Supprimée',
        annulee => 'Annulée',
        _ => s.isEmpty ? 'Inconnu' : s,
      };
}

/// En-tête d'une suggestion.
class EnteteSuggestion {
  final String id;
  final String ref;
  final SensReserve sens;
  final OrigineSuggestion origine;
  final String statut;
  final String commentaire;
  final int? motifId;
  final String motifLibelle;
  final String createur;
  final String traitant;
  final String dateCreation;
  final String dateTraitement;
  final int nbProduits;

  const EnteteSuggestion({
    required this.id,
    required this.ref,
    required this.sens,
    required this.origine,
    required this.statut,
    this.commentaire = '',
    this.motifId,
    this.motifLibelle = '',
    this.createur = '',
    this.traitant = '',
    this.dateCreation = '',
    this.dateTraitement = '',
    this.nbProduits = 0,
  });

  factory EnteteSuggestion.fromJson(Map<String, dynamic> j) => EnteteSuggestion(
        id: txt(j['lg_SUGGESTION_RESERVE_ID']),
        ref: txt(j['str_REF']),
        sens: SensReserve.depuisCategorie(j['str_CATEGORIE']),
        origine: OrigineSuggestion.lire(j['str_ORIGINE']),
        statut: txt(j['str_STATUT']).toUpperCase(),
        commentaire: txt(j['str_COMMENTAIRE']),
        motifId: entier(j['motif_id']),
        motifLibelle: txt(j['motif_libelle']),
        createur: txt(j['str_USER_CREATEUR']),
        traitant: txt(j['str_USER_TRAITANT']),
        dateCreation: txt(j['dt_CREATED']),
        dateTraitement: txt(j['dt_TRAITEE']),
        nbProduits: entier0(j['nb_produits']),
      );

  /// Encore à traiter (A_TRAITER ou EN_COURS).
  bool get ouverte => statut == StatutSuggestion.aTraiter || statut == StatutSuggestion.enCours;
}

/// États d'une ligne.
class EtatLigne {
  EtatLigne._();
  static const proposee = 'PROPOSEE';
  static const modifiee = 'MODIFIEE';
  static const traitee = 'TRAITEE';
  static const echec = 'ECHEC';
  static const supprimee = 'SUPPRIMEE';
  static const annulee = 'ANNULEE';

  static String libelle(String e) => switch (e) {
        proposee => 'Proposée',
        modifiee => 'Vérifiée',
        traitee => 'Déplacée',
        echec => 'En échec',
        supprimee => 'Retirée',
        annulee => 'Annulée',
        _ => e.isEmpty ? '—' : e,
      };
}

/// Ligne d'une suggestion.
class LigneSuggestion {
  final String detailId;
  final String familleId;
  final String cip;
  final String nom;
  final int qteProposee;
  final int? qteRetenue;
  final int qteDeplacee;
  final int stockRayonCreation;
  final int stockReserveCreation;
  final int? stockRayonActuel;
  final int? stockReserveActuel;
  final int? propositionActuelle;
  final String formule;
  final String etat;
  final String codeEchec;
  final String motifLigne;

  /// Raison de non-traitement (compte rendu seulement).
  final String raison;

  const LigneSuggestion({
    required this.detailId,
    required this.familleId,
    required this.cip,
    required this.nom,
    required this.qteProposee,
    this.qteRetenue,
    this.qteDeplacee = 0,
    this.stockRayonCreation = 0,
    this.stockReserveCreation = 0,
    this.stockRayonActuel,
    this.stockReserveActuel,
    this.propositionActuelle,
    this.formule = '',
    this.etat = '',
    this.codeEchec = '',
    this.motifLigne = '',
    this.raison = '',
  });

  factory LigneSuggestion.fromJson(Map<String, dynamic> j) => LigneSuggestion(
        detailId: txt(j['lg_SUGGESTION_RESERVE_DETAIL_ID']),
        familleId: txt(j['lg_FAMILLE_ID']),
        cip: txt(j['int_CIP']),
        nom: txt(j['str_NAME']),
        qteProposee: entier0(j['int_QTE_PROPOSEE']),
        qteRetenue: entier(j['int_QTE_RETENUE']),
        qteDeplacee: entier0(j['int_QTE_DEPLACEE']),
        stockRayonCreation: entier0(j['int_STOCK_RAYON']),
        stockReserveCreation: entier0(j['int_STOCK_RESERVE']),
        stockRayonActuel: entier(j['int_STOCK_RAYON_ACTUEL']),
        stockReserveActuel: entier(j['int_STOCK_RESERVE_ACTUEL']),
        propositionActuelle: entier(j['int_PROPOSITION_ACTUELLE']),
        formule: txt(j['str_FORMULE']),
        etat: txt(j['str_ETAT']).toUpperCase(),
        codeEchec: txt(j['str_CODE_ECHEC']),
        motifLigne: txt(j['str_MOTIF_LIGNE']),
        raison: txt(j['str_RAISON']),
      );

  /// Quantité qui sera déplacée au traitement (retenue, sinon proposée) — comme le serveur.
  int get qteATraiter => qteRetenue ?? qteProposee;

  /// Stock rayon à afficher (actuel si connu).
  int get stockRayon => stockRayonActuel ?? stockRayonCreation;

  /// Stock réserve à afficher (actuel si connu).
  int get stockReserve => stockReserveActuel ?? stockReserveCreation;

  /// Stock d'où partent les boîtes.
  int disponible(SensReserve sens) => sens == SensReserve.versReserve ? stockRayon : stockReserve;

  /// La quantité peut encore être changée (ni déplacée, ni annulée, ni retirée).
  bool get modifiable => etat != EtatLigne.traitee && etat != EtatLigne.annulee && etat != EtatLigne.supprimee;

  /// Sera prise par « Traiter » (même règle que le serveur : estTraitable).
  bool get traitable => modifiable && qteATraiter > 0;

  LigneSuggestion avecQuantite(int qte) => LigneSuggestion(
        detailId: detailId,
        familleId: familleId,
        cip: cip,
        nom: nom,
        qteProposee: qteProposee,
        qteRetenue: qte,
        qteDeplacee: qteDeplacee,
        stockRayonCreation: stockRayonCreation,
        stockReserveCreation: stockReserveCreation,
        stockRayonActuel: stockRayonActuel,
        stockReserveActuel: stockReserveActuel,
        propositionActuelle: propositionActuelle,
        formule: formule,
        etat: EtatLigne.modifiee,
        codeEchec: codeEchec,
        motifLigne: motifLigne,
      );
}

/// Suggestion ouverte pour traitement (PUT {id}/ouvrir) : prend le verrou si personne ne l'occupe.
class SuggestionOuverte {
  final EnteteSuggestion entete;
  final List<LigneSuggestion> lignes;

  /// Saisie et traitement possibles (verrou détenu, suggestion non close).
  final bool modifiable;
  final String verrouPar;
  final String verrouDepuis;
  final String motifLectureSeule;

  const SuggestionOuverte({
    required this.entete,
    required this.lignes,
    required this.modifiable,
    this.verrouPar = '',
    this.verrouDepuis = '',
    this.motifLectureSeule = '',
  });

  factory SuggestionOuverte.fromJson(Map<String, dynamic> j) => SuggestionOuverte(
        entete: EnteteSuggestion.fromJson(objet(j['entete'])),
        lignes: [for (final o in objets(j['lignes'])) LigneSuggestion.fromJson(o)],
        // Absent (ancienne réponse « détail ») : prudence, lecture seule.
        modifiable: booleen(j['modifiable']),
        verrouPar: txt(j['verrou_par']),
        verrouDepuis: txt(j['verrou_depuis']),
        motifLectureSeule: txt(j['motif_lecture_seule']),
      );

  /// Occupée par un autre utilisateur (verrou de 20 min côté serveur).
  bool get occupeeParAutre => !modifiable && verrouPar.isNotEmpty;

  SuggestionOuverte avecLignes(List<LigneSuggestion> l) => SuggestionOuverte(
      entete: entete, lignes: l, modifiable: modifiable, verrouPar: verrouPar, verrouDepuis: verrouDepuis, motifLectureSeule: motifLectureSeule);
}

/// Compte rendu d'un traitement (PUT {id}/traiter, {id}/reessayer).
class CompteRendu {
  final EnteteSuggestion entete;
  final int totalDemande;
  final int totalReussi;
  final int totalEchoue;
  final int totalSupprime;
  final int totalIgnore;
  final List<LigneSuggestion> traites;
  final List<LigneSuggestion> nonTraites;
  final bool relancable;

  const CompteRendu({
    required this.entete,
    this.totalDemande = 0,
    this.totalReussi = 0,
    this.totalEchoue = 0,
    this.totalSupprime = 0,
    this.totalIgnore = 0,
    this.traites = const [],
    this.nonTraites = const [],
    this.relancable = false,
  });

  factory CompteRendu.fromJson(Map<String, dynamic> j) => CompteRendu(
        entete: EnteteSuggestion.fromJson(objet(j['entete'])),
        totalDemande: entier0(j['total_demande']),
        totalReussi: entier0(j['total_reussi']),
        totalEchoue: entier0(j['total_echoue']),
        totalSupprime: entier0(j['total_supprime']),
        totalIgnore: entier0(j['total_ignore']),
        traites: [for (final o in objets(j['articles_traites'])) LigneSuggestion.fromJson(o)],
        nonTraites: [for (final o in objets(j['articles_non_traites'])) LigneSuggestion.fromJson(o)],
        relancable: booleen(j['relancable']),
      );

  /// Boîtes réellement déplacées.
  int get boitesDeplacees => traites.fold(0, (s, l) => s + l.qteDeplacee);
}

/// Réponse de POST creer.
class ResultatCreation {
  final String id;
  final String ref;
  final int lignes;
  final int ignorees;
  final String message;
  const ResultatCreation({required this.id, this.ref = '', this.lignes = 0, this.ignorees = 0, this.message = ''});

  factory ResultatCreation.fromJson(Map<String, dynamic> j) => ResultatCreation(
        id: txt(j['lg_SUGGESTION_RESERVE_ID']),
        ref: txt(j['str_REF']),
        lignes: entier0(j['lignes']),
        ignorees: entier0(j['ignorees']),
        message: txt(j['message']),
      );
}

/// Ligne du panier d'un réappro manuel (avant création de la suggestion).
class LignePanier {
  final ArticleReserve article;
  final int quantite;
  const LignePanier(this.article, this.quantite);
}
