// lib/borne/borne_produit.dart
// Produit présenté à la borne : forme déduite du nom (pictogramme + couleur, en attendant les
// images B2), disponibilité, et champ image (null tant que le serveur n'en fournit pas).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/models/product.dart';

enum FormeProduit { comprime, gelule, sirop, creme, collyre, suppositoire, injectable, sachet, spray, lait, savon, autre }

extension FormeProduitInfo on FormeProduit {
  String get label => switch (this) {
        FormeProduit.comprime => 'Comprimés',
        FormeProduit.gelule => 'Gélules',
        FormeProduit.sirop => 'Sirop / buvable',
        FormeProduit.creme => 'Crème / gel / pommade',
        FormeProduit.collyre => 'Collyre / gouttes',
        FormeProduit.suppositoire => 'Suppositoires',
        FormeProduit.injectable => 'Injectable',
        FormeProduit.sachet => 'Sachets / poudre',
        FormeProduit.spray => 'Spray / aérosol',
        FormeProduit.lait => 'Lait / alimentation',
        FormeProduit.savon => 'Hygiène',
        FormeProduit.autre => 'Produit',
      };

  IconData get icon => switch (this) {
        FormeProduit.comprime => Icons.medication,
        FormeProduit.gelule => Icons.medication_outlined,
        FormeProduit.sirop => Icons.local_drink,
        FormeProduit.creme => Icons.soap,
        FormeProduit.collyre => Icons.water_drop,
        FormeProduit.suppositoire => Icons.egg_alt,
        FormeProduit.injectable => Icons.vaccines,
        FormeProduit.sachet => Icons.inventory_2,
        FormeProduit.spray => Icons.air,
        FormeProduit.lait => Icons.child_care,
        FormeProduit.savon => Icons.clean_hands,
        FormeProduit.autre => Icons.local_pharmacy,
      };

  /// (fond, encre) : contraste élevé (encre foncée sur fond pâle).
  (Color, Color) get couleurs => switch (this) {
        FormeProduit.comprime || FormeProduit.gelule => (const Color(0xFFE3ECF7), const Color(0xFF003366)),
        FormeProduit.sirop => (const Color(0xFFFFF4E0), const Color(0xFF8A3A00)),
        FormeProduit.creme || FormeProduit.savon => (const Color(0xFFFDECEC), const Color(0xFF8B1C1C)),
        FormeProduit.collyre => (const Color(0xFFE0F2FE), const Color(0xFF075985)),
        FormeProduit.suppositoire => (const Color(0xFFF3E8FF), const Color(0xFF5B21B6)),
        FormeProduit.injectable => (const Color(0xFFFFE4E6), const Color(0xFF9F1239)),
        FormeProduit.sachet => (const Color(0xFFECFCCB), const Color(0xFF3F6212)),
        FormeProduit.spray => (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
        FormeProduit.lait => (const Color(0xFFE6F4EA), const Color(0xFF166534)),
        FormeProduit.autre => (const Color(0xFFEEF2F7), const Color(0xFF14213D)),
      };
}

/// Forme déduite du nom (abréviations Prestige : CP, CPR, GEL, SP, SIROP, SUSP BUV, CR, COLL, SUPPO, INJ, SACH, SPRAY…).
FormeProduit formeDuNom(String nom) {
  final n = ' ${nom.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9%,]+'), ' ')} ';
  bool a(List<String> mots) => mots.any((m) => n.contains(' $m ') || (m.length >= 5 && n.contains(m)));
  if (a(['INJ', 'INJECTABLE', 'AMP', 'AMPOULE', 'SERINGUE', 'IM', 'IV', 'PERF'])) return FormeProduit.injectable;
  if (a(['COLLYRE', 'COLL', 'COLLY', 'GTT', 'GOUTTES', 'GOUTTE', 'AURIC', 'OPHT'])) return FormeProduit.collyre;
  if (a(['SUPPO', 'SUPP', 'SUPPOSITOIRE', 'SUPPOSITOIRES', 'OVULE', 'OVULES'])) return FormeProduit.suppositoire;
  if (a(['SPRAY', 'AEROSOL', 'NASAL', 'INHAL', 'PULV'])) return FormeProduit.spray;
  if (a(['SIROP', 'SIR', 'SP', 'SUSP', 'BUV', 'SOL', 'SOLUTION', 'FL', 'FLACON', 'ELIXIR'])) return FormeProduit.sirop;
  if (a(['CREME', 'CR', 'GEL', 'POMMADE', 'POM', 'PDE', 'LOTION', 'BAUME', 'EMULSION'])) return FormeProduit.creme;
  if (a(['SACHET', 'SACHETS', 'SACH', 'SACHETS', 'PDR', 'POUDRE', 'GRANULES', 'GRANULE'])) return FormeProduit.sachet;
  if (a(['GELULE', 'GELULES', 'GLE', 'CAPS', 'CAPSULE'])) return FormeProduit.gelule;
  if (a(['CP', 'CPR', 'CPS', 'COMP', 'COMPRIME', 'COMPRIMES', 'EFFV', 'EFF', 'LP', 'ORODISP'])) return FormeProduit.comprime;
  if (a(['LAIT', 'FARINE', 'CEREALE', 'BIBERON'])) return FormeProduit.lait;
  if (a(['SAVON', 'SHAMPOING', 'SHAMP', 'DENTIFRICE', 'INTIME', 'DOUCHE', 'HYGIENE'])) return FormeProduit.savon;
  return FormeProduit.autre;
}

/// Produit de la borne.
class BorneProduit {
  final ProductSearchResult source;

  /// Adresse de l'image (B2) ; null : pictogramme de la forme.
  final String? image;
  const BorneProduit(this.source, {this.image});

  String get id => source.lgFAMILLEID;
  String get nom => source.strNAME.trim();
  String get code => source.intCIP.trim();
  int get prix => source.intPRICE;
  int get stock => source.intNUMBERAVAILABLE;
  bool get disponible => stock > 0 && prix > 0;
  bool get aImage => image != null && image!.isNotEmpty;
  FormeProduit get forme => formeDuNom(nom);
}

/// Produits avec image d'abord (demande du client), puis disponibles, ordre du serveur conservé sinon.
List<BorneProduit> trierPourBorne(List<BorneProduit> produits) {
  final indexed = [for (var i = 0; i < produits.length; i++) (i, produits[i])];
  indexed.sort((a, b) {
    int rang(BorneProduit p) => (p.aImage ? 0 : 2) + (p.disponible ? 0 : 1);
    final r = rang(a.$2).compareTo(rang(b.$2));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
