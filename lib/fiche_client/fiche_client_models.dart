// lib/fiche_client/fiche_client_models.dart
// Fiche client des ordonnances (routes v1/ordonnance-client/… de Prestige).
// DONNÉES DE SANTÉ : gardées en mémoire le temps de l'écran seulement — jamais journalisées, jamais écrites
// sur le disque (ni préférences, ni base locale, ni fichier).
import 'package:prestige_vente_app/serveur/json_tolerant.dart';

/// Client trouvé par la recherche (GET clients).
class ClientResume {
  final String id;
  final String nom;
  final String prenoms;
  final String telephone;
  final String type;
  final String naissance;
  final String sexe;

  const ClientResume({required this.id, required this.nom, this.prenoms = '', this.telephone = '', this.type = '', this.naissance = '', this.sexe = ''});

  factory ClientResume.fromJson(Map<String, dynamic> j) => ClientResume(
        id: txt(j['lgCLIENTID'] ?? j['id']),
        nom: txt(j['strFIRSTNAME'] ?? j['nom']),
        prenoms: txt(j['strLASTNAME'] ?? j['prenoms']),
        telephone: txt(j['strTELEPHONE'] ?? j['telephone']),
        type: txtOuNull(j['libelleTypeClient']) ?? txt(j['typeClient'] ?? j['type']),
        naissance: txt(j['dtNAISSANCE'] ?? j['naissance']),
        sexe: txt(j['strSEXE'] ?? j['sexe']),
      );

  String get nomComplet => '$nom $prenoms'.trim();
}

/// Identité du dossier (lecture seule dans Prestige depuis ce menu).
class IdentiteClient {
  final String id;
  final String nom;
  final String prenoms;
  final String telephone;
  final String naissance;
  final int? age;
  final String sexe;
  final String type;

  const IdentiteClient({required this.id, this.nom = '', this.prenoms = '', this.telephone = '', this.naissance = '', this.age, this.sexe = '', this.type = ''});

  factory IdentiteClient.fromJson(Map<String, dynamic> j) => IdentiteClient(
        id: txt(j['id']),
        nom: txt(j['nom']),
        prenoms: txt(j['prenoms']),
        telephone: txt(j['telephone']),
        naissance: txt(j['naissance']),
        age: entier(j['age']),
        sexe: txt(j['sexe']),
        type: txt(j['type']),
      );

  String get nomComplet => '$nom $prenoms'.trim();
}

/// Dernière valeur d'un paramètre suivi (tension, poids…) dans le dossier.
class ParametreSuivi {
  final String parametreId;
  final String code;
  final String libelle;
  final String unite;
  final String genre;
  final int decimales;
  final int nbMesures;
  final double? valeur;
  final double? valeur2;
  final String cote;
  final String date;
  final String etat;
  final String analyse;
  final String norme;

  const ParametreSuivi({
    required this.parametreId,
    this.code = '',
    required this.libelle,
    this.unite = '',
    this.genre = 'simple',
    this.decimales = 0,
    this.nbMesures = 0,
    this.valeur,
    this.valeur2,
    this.cote = '',
    this.date = '',
    this.etat = '',
    this.analyse = '',
    this.norme = '',
  });

  factory ParametreSuivi.fromJson(Map<String, dynamic> j) => ParametreSuivi(
        parametreId: txt(j['parametreId']),
        code: txt(j['code']).toUpperCase(),
        libelle: txtOuNull(j['libelle']) ?? 'Paramètre',
        unite: txt(j['unite']),
        genre: txt(j['genre']).toLowerCase() == 'tension' ? 'tension' : 'simple',
        decimales: (entier(j['decimales']) ?? 0).clamp(0, 3),
        nbMesures: entier0(j['nbMesures']),
        valeur: decimal(j['valeur']),
        valeur2: decimal(j['valeur2']),
        cote: txt(j['cote']),
        date: txt(j['date']),
        etat: txt(j['etat']),
        analyse: txt(j['analyse']),
        norme: txt(j['norme']),
      );

  bool get tension => genre == 'tension';
  bool get mesure => valeur != null;
}

/// IMC calculé par le serveur (poids et taille).
class Imc {
  final double valeur;
  final String etat;
  final String analyse;
  const Imc({required this.valeur, this.etat = '', this.analyse = ''});

  static Imc? fromJson(Object? v) {
    final j = objet(v);
    final val = decimal(j['valeur']);
    return val == null ? null : Imc(valeur: val, etat: txt(j['etat']), analyse: txt(j['analyse']));
  }
}

/// Dossier complet (GET client/{id}/dossier).
class DossierClient {
  final IdentiteClient client;
  final List<String> terrains;
  final String allergies;
  final List<ParametreSuivi> parametres;
  final Imc? imc;
  final int nbOrdonnances;

  const DossierClient({required this.client, this.terrains = const [], this.allergies = '', this.parametres = const [], this.imc, this.nbOrdonnances = 0});

  factory DossierClient.fromJson(Map<String, dynamic> j) => DossierClient(
        client: IdentiteClient.fromJson(objet(j['client'])),
        terrains: textes(j['terrains']),
        allergies: txt(j['allergies']),
        parametres: [for (final o in objets(j['parametres'])) ParametreSuivi.fromJson(o)]..removeWhere((p) => p.parametreId.isEmpty),
        imc: Imc.fromJson(j['imc']),
        nbOrdonnances: entier0(j['nbOrdonnances']),
      );
}

/// Terrain clinique ou allergie du référentiel (GET terrains).
class TerrainClinique {
  final String id;
  final String code;
  final String libelle;
  final bool allergie;
  final bool actif;
  const TerrainClinique({required this.id, this.code = '', required this.libelle, this.allergie = false, this.actif = true});

  factory TerrainClinique.fromJson(Map<String, dynamic> j) => TerrainClinique(
        id: txt(j['id']),
        code: txt(j['code']),
        libelle: txtOuNull(j['libelle']) ?? txt(j['code']),
        allergie: txt(j['categorie']).toLowerCase() == 'allergie',
        actif: j.containsKey('actif') ? booleen(j['actif']) : true,
      );
}

/// Paramètre clinique du référentiel (GET parametres) : bornes de saisie fixées dans Prestige.
class ParametreClinique {
  final String id;
  final String code;
  final String libelle;
  final String unite;
  final String genre;
  final int decimales;
  final double? saisieMin;
  final double? saisieMax;
  final bool actif;

  const ParametreClinique({
    required this.id,
    this.code = '',
    required this.libelle,
    this.unite = '',
    this.genre = 'simple',
    this.decimales = 0,
    this.saisieMin,
    this.saisieMax,
    this.actif = true,
  });

  factory ParametreClinique.fromJson(Map<String, dynamic> j) => ParametreClinique(
        id: txt(j['id']),
        code: txt(j['code']).toUpperCase(),
        libelle: txtOuNull(j['libelle']) ?? 'Paramètre',
        unite: txt(j['unite']),
        genre: txt(j['genre']).toLowerCase() == 'tension' ? 'tension' : 'simple',
        decimales: (entier(j['decimales']) ?? 0).clamp(0, 3),
        saisieMin: decimal(j['saisieMin']),
        saisieMax: decimal(j['saisieMax']),
        actif: j.containsKey('actif') ? booleen(j['actif']) : true,
      );

  bool get tension => genre == 'tension';
}

/// Mesure datée (GET client/{id}/mesures).
class Mesure {
  final String id;
  final double? valeur;
  final double? valeur2;
  final String cote;
  final String date;
  final String commentaire;
  final String par;
  final String etat;
  final String analyse;
  const Mesure({this.id = '', this.valeur, this.valeur2, this.cote = '', this.date = '', this.commentaire = '', this.par = '', this.etat = '', this.analyse = ''});

  factory Mesure.fromJson(Map<String, dynamic> j) => Mesure(
        id: txt(j['id']),
        valeur: decimal(j['valeur']),
        valeur2: decimal(j['valeur2']),
        cote: txt(j['cote']),
        date: txt(j['date']),
        commentaire: txt(j['commentaire']),
        par: txt(j['par']),
        etat: txt(j['etat']),
        analyse: txt(j['analyse']),
      );
}

/// Produit du suivi de consommation (12 mois par défaut).
class LigneConsommation {
  final String cip;
  final String nom;
  final String dernierAchat;
  final int nbAchats;
  final int qteTotale;
  final int? frequenceJours;
  final int montant;
  final String habitude;
  final int? stock;

  const LigneConsommation({this.cip = '', required this.nom, this.dernierAchat = '', this.nbAchats = 0, this.qteTotale = 0, this.frequenceJours, this.montant = 0, this.habitude = '', this.stock});

  factory LigneConsommation.fromJson(Map<String, dynamic> j) => LigneConsommation(
        cip: txt(j['cip']),
        nom: txtOuNull(j['name']) ?? txt(j['nom']),
        dernierAchat: txt(j['dernierAchat']),
        nbAchats: entier0(j['nbAchats']),
        qteTotale: entier0(j['qteTotale']),
        frequenceJours: entier(j['frequenceJours']),
        montant: entier0(j['montant']),
        habitude: txt(j['habitude']),
        stock: entier(j['stock']),
      );
}

/// Affichage d'une valeur avec le nombre de décimales du paramètre (virgule française).
String formaterValeur(double? v, int decimales) {
  if (v == null) return '—';
  return v.toStringAsFixed(decimales.clamp(0, 3)).replaceAll('.', ',');
}

/// « 13,5/8,2 mmHg » ou « 72,5 kg ».
String formaterParametre(ParametreSuivi p) {
  if (!p.mesure) return 'Non mesuré';
  final v = p.tension && p.valeur2 != null
      ? '${formaterValeur(p.valeur, p.decimales)}/${formaterValeur(p.valeur2, p.decimales)}'
      : formaterValeur(p.valeur, p.decimales);
  return p.unite.isEmpty ? v : '$v ${p.unite}';
}
