// lib/paiements/mode_paiement_logo.dart
// Image d'un mode de paiement (écrans de vente et listes de règlements) : logo fourni par la pharmacie
// pour le mobile money (Wave, Djamo, Moov Money, MTN MoMo, Orange Money), pictogramme dessiné
// (icône Material dans un cercle coloré) pour les autres modes. Résolution par id Prestige, puis par
// libellé (insensible à la casse et aux accents) quand l'id est inconnu. Purement visuel : ne change
// ni la sélection ni les valeurs envoyées au serveur. Jamais d'exception : asset manquant → pictogramme.
import 'package:flutter/material.dart';

/// Familles de modes de paiement affichables.
enum ModePaiementType { especes, cheque, carte, differe, virement, orange, moov, mtn, wave, djamo, inconnu }

/// Apparence d'un mode : [asset] (logo fourni) ou pictogramme [icone] sur fond [couleur].
class ModePaiementVisuel {
  final ModePaiementType type;
  final String nom;
  final String? asset;
  final IconData icone;
  final Color couleur;
  const ModePaiementVisuel(this.type, this.nom, this.icone, this.couleur, {this.asset});
}

/// Dossier des logos fournis (déclaré dans pubspec.yaml).
const String dossierLogosPaiement = 'assets/paiements/';

const Map<ModePaiementType, ModePaiementVisuel> visuelsModesPaiement = {
  ModePaiementType.especes: ModePaiementVisuel(ModePaiementType.especes, 'Espèces', Icons.payments, Color(0xFF15803D)),
  ModePaiementType.cheque: ModePaiementVisuel(ModePaiementType.cheque, 'Chèque', Icons.receipt_long, Color(0xFF475569)),
  ModePaiementType.carte: ModePaiementVisuel(ModePaiementType.carte, 'Carte bancaire', Icons.credit_card, Color(0xFF3730A3)),
  ModePaiementType.differe: ModePaiementVisuel(ModePaiementType.differe, 'Différé', Icons.schedule, Color(0xFFB45309)),
  ModePaiementType.virement: ModePaiementVisuel(ModePaiementType.virement, 'Virement', Icons.swap_horiz, Color(0xFF0F766E)),
  ModePaiementType.orange: ModePaiementVisuel(ModePaiementType.orange, 'Orange Money', Icons.phone_android, Color(0xFFFF7900),
      asset: '${dossierLogosPaiement}orange.png'),
  ModePaiementType.moov: ModePaiementVisuel(ModePaiementType.moov, 'Moov Money', Icons.phone_android, Color(0xFFF37021),
      asset: '${dossierLogosPaiement}moov.png'),
  ModePaiementType.mtn: ModePaiementVisuel(ModePaiementType.mtn, 'MTN MoMo', Icons.phone_android, Color(0xFFFFCB05),
      asset: '${dossierLogosPaiement}mtn.png'),
  ModePaiementType.wave: ModePaiementVisuel(ModePaiementType.wave, 'Wave', Icons.phone_android, Color(0xFF1DC3F0),
      asset: '${dossierLogosPaiement}wave.png'),
  ModePaiementType.djamo: ModePaiementVisuel(ModePaiementType.djamo, 'Djamo', Icons.phone_android, Color(0xFF111111),
      asset: '${dossierLogosPaiement}djamo.png'),
  ModePaiementType.inconnu: ModePaiementVisuel(ModePaiementType.inconnu, 'Mode de paiement', Icons.account_balance_wallet, Color(0xFF64748B)),
};

/// Modes Prestige connus (lgTYPEREGLEMENTID).
const Map<String, ModePaiementType> modesPaiementParId = {
  '1': ModePaiementType.especes,
  '2': ModePaiementType.cheque,
  '3': ModePaiementType.carte,
  '4': ModePaiementType.differe,
  '6': ModePaiementType.virement,
  '7': ModePaiementType.orange,
  '8': ModePaiementType.moov,
  '9': ModePaiementType.mtn,
  '10': ModePaiementType.wave,
  '19': ModePaiementType.djamo,
};

/// Chemins des logos fournis (tests : présence et chargement).
List<String> get assetsModesPaiement => [for (final v in visuelsModesPaiement.values) if (v.asset != null) v.asset!];

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ç': 'c', 'ñ': 'n',
};

String _normaliser(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    b.write(_accents[c] ?? c);
  }
  return b.toString();
}

/// Mode d'après le libellé (« WAVE », « Orange Money », « OM », « MTN MoMo », « Espèces »…), sinon inconnu.
ModePaiementType modePaiementParLibelle(String? libelle) {
  final n = _normaliser((libelle ?? '').trim());
  if (n.isEmpty) return ModePaiementType.inconnu;
  final mots = n.split(RegExp(r'[^a-z0-9]+')).where((m) => m.isNotEmpty).toSet();
  bool a(String s) => n.contains(s);
  // Opérateurs d'abord (« Orange Money » / « Moov Money » contiennent « money »).
  if (a('wave')) return ModePaiementType.wave;
  if (a('djamo')) return ModePaiementType.djamo;
  if (a('orange') || mots.contains('om')) return ModePaiementType.orange;
  if (a('moov') || a('flooz')) return ModePaiementType.moov;
  if (a('mtn') || a('momo')) return ModePaiementType.mtn;
  if (a('espece') || a('cash') || a('liquide') || mots.contains('esp')) return ModePaiementType.especes;
  if (a('cheque') || mots.contains('chq')) return ModePaiementType.cheque;
  if (a('virement') || a('transfert') || a('transfer')) return ModePaiementType.virement;
  if (a('carte') || a('card') || a('visa') || a('mastercard') || mots.contains('cb') || mots.contains('tpe')) return ModePaiementType.carte;
  if (a('differe') || a('credit') || a('terme') || a('compte client')) return ModePaiementType.differe;
  return ModePaiementType.inconnu;
}

/// Mode d'un règlement : par id Prestige connu, sinon par libellé, sinon inconnu.
ModePaiementType resoudreModePaiement({String? modeId, String? libelle}) {
  final parId = modesPaiementParId[(modeId ?? '').trim()];
  if (parId != null) return parId;
  return modePaiementParLibelle(libelle);
}

/// Apparence résolue (voir [resoudreModePaiement]).
ModePaiementVisuel visuelModePaiement({String? modeId, String? libelle}) =>
    visuelsModesPaiement[resoudreModePaiement(modeId: modeId, libelle: libelle)]!;

/// Logo rond d'un mode de paiement ([size] 24–48 selon l'écran). Le libellé reste affiché à côté par
/// l'écran appelant ; ici, seul le nom lu par l'accessibilité.
class ModePaiementLogo extends StatelessWidget {
  final String? modeId;
  final String? libelle;
  final double size;

  /// Apparence imposée (tests du repli : logo absent) ; sinon résolue par [modeId] / [libelle].
  final ModePaiementVisuel? visuel;
  const ModePaiementLogo({super.key, this.modeId, this.libelle, this.size = 32}) : visuel = null;
  const ModePaiementLogo.depuisVisuel(ModePaiementVisuel this.visuel, {super.key, this.libelle, this.size = 32}) : modeId = null;

  @override
  Widget build(BuildContext context) {
    final v = visuel ?? visuelModePaiement(modeId: modeId, libelle: libelle);
    final nom = (libelle ?? '').trim().isNotEmpty ? libelle!.trim() : v.nom;
    final asset = v.asset;
    final Widget contenu = asset == null
        ? _ModePictogramme(visuel: v, size: size)
        : DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0x22000000), width: 0.8),
            ),
            child: ClipOval(
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => _ModePictogramme(visuel: visuelsModesPaiement[ModePaiementType.inconnu]!, size: size),
              ),
            ),
          );
    return Semantics(
      label: 'Mode de paiement : $nom',
      image: true,
      excludeSemantics: true,
      child: SizedBox(key: ValueKey('logo-mode-${v.type.name}'), width: size, height: size, child: contenu),
    );
  }
}

/// Pictogramme : icône blanche sur un cercle de la couleur du mode (lisible en thème clair et sombre).
class _ModePictogramme extends StatelessWidget {
  final ModePaiementVisuel visuel;
  final double size;
  const _ModePictogramme({required this.visuel, required this.size});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: ValueKey('picto-mode-${visuel.type.name}'),
        decoration: BoxDecoration(shape: BoxShape.circle, color: visuel.couleur),
        child: Center(child: Icon(visuel.icone, size: size * 0.58, color: Colors.white)),
      );
}
