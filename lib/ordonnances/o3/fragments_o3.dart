// lib/ordonnances/o3/fragments_o3.dart
// Étape O3b : reconnaissance par FRAGMENTS SÛRS (« contient », avec prudence).
//
// Quand un nom n'est lisible qu'en partie (« arphos Ab », « Lufar 80/480 »), on garde les morceaux jugés fiables et
// on cherche les produits du catalogue qui les CONTIENNENT :
//  - fiabilité : confiance par caractère de ML Kit quand elle existe (Android : symboles, voir [ConfianceLecture]) ;
//    sinon heuristique : coupure aux lettres qui naissent des confusions à plusieurs lettres (m ↔ rn / nn / iu,
//    d ↔ cl, w ↔ vv) et aux groupes « rn », « cl », « ii » ; les confusions d'une lettre (u/n, a/o, i/l/1, e/c, o/0)
//    sont neutralisées par un « pliage » commun au fragment et au catalogue (u→n, a→o, l/1→i, c→e, 0→o) ;
//  - fragments de 4 caractères au moins (3 interdits) ;
//  - recherche par index de TRIGRAMMES du catalogue local (rapide : < 50 ms par ligne sur 10 000 produits) ; sans
//    copie locale : recherche serveur avec le joker % (« %frag1%frag2 »), bornée à 50 produits ;
//  - plusieurs fragments combinés (ET pondéré par la longueur, bonus si l'ordre est respecté), dosage et forme lus
//    (filtre / bonus), bonus apprentissages O4, produits vendus et en stock ;
//  - fragment trop fréquent (> 30 produits, ex. « amox », « para ») ignoré, sauf combiné au dosage / à la forme lus
//    qui ramènent le choix à 30 produits au plus.
// GARDE-FOUS : ces propositions viennent APRÈS les correspondances complètes, sont plafonnées à 3, toujours
// « À vérifier » (confiance < seuil sûr, jamais cochées d'office), avec l'indication « trouvé par fragment : …PHOS… ».
import 'dart:math' as math;

import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';
import 'package:prestige_vente_app/ordonnances/o4/segment_medicament.dart';

/// Confiance de lecture par caractère, enregistrée par la lecture ML Kit (Android) : masque « 1 » fiable / « 0 »
/// douteux par caractère de chaque ligne lue. Vide (iOS, tesseract, PDF…) : heuristique seule.
abstract final class ConfianceLecture {
  /// Seuil de confiance d'un caractère (symbole ML Kit) pour être « sûr ».
  static const double seuil = 0.6;

  static final Map<String, String> _masques = {};

  /// Masques de la dernière lecture (remplacés à chaque lecture ; jamais enregistrés ni envoyés).
  static void remplacer(Map<String, String> masques) {
    _masques
      ..clear()
      ..addAll(masques);
  }

  static void vider() => _masques.clear();

  /// Masque de [texte] (sous-partie d'une ligne lue), ou null si inconnu.
  static String? masquePour(String texte) {
    if (_masques.isEmpty || texte.isEmpty) return null;
    final m = List<String>.filled(texte.length, '1');
    var trouve = false;
    for (final e in _masques.entries) {
      final ligne = e.key, masque = e.value;
      if (masque.length != ligne.length || ligne.isEmpty) continue;
      final i = ligne.indexOf(texte);
      if (i >= 0) return masque.substring(i, i + texte.length);
      final j = texte.indexOf(ligne);
      if (j >= 0) {
        for (var k = 0; k < ligne.length; k++) {
          m[j + k] = masque[k];
        }
        trouve = true;
      }
    }
    return trouve ? m.join() : null;
  }
}

/// Un fragment sûr : texte lu (pour l'affichage) et forme pliée (pour la recherche).
class FragmentSur {
  final String brut;
  final String plie;
  const FragmentSur(this.brut, this.plie);

  @override
  String toString() => brut;
}

/// Proposition trouvée par fragments.
class PropositionFragment {
  final ProductSearchResult produit;
  final double confiance;

  /// « …PHOS… » ou « …LUFA…  …480… ».
  final String indication;
  const PropositionFragment(this.produit, this.confiance, this.indication);
}

abstract final class FragmentsO3 {
  static const int longueurMin = 4;

  /// Au-delà, un fragment seul est trop fréquent (ignoré sauf avec dosage / forme).
  static const int frequenceMax = 30;

  /// Propositions par fragments au plus.
  static const int maximum = 3;

  /// Confiance maximale d'une proposition par fragments (toujours sous le seuil « sûr » d'O3 : 0,80).
  static const double confianceMax = 0.79;

  /// Confiance minimale pour être montrée.
  static const double confianceMin = 0.55;

  /// Pliage des confusions d'une lettre (même pliage pour le fragment et le catalogue).
  static String plier(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      b.write(switch (c) {
        'u' => 'n',
        'a' => 'o',
        '0' => 'o',
        'l' => 'i',
        '1' => 'i',
        'c' => 'e',
        _ => c,
      });
    }
    return b.toString();
  }

  /// Lettres qui naissent d'une confusion à plusieurs lettres : jamais dans un fragment sûr.
  static const _coupures = {'m', 'd', 'w'};

  /// Groupes de deux lettres ambigus (« rn » ↔ m, « cl » ↔ d, « ii » ↔ u, « nn » ↔ m, « iu » ↔ m) : retirés.
  static final _groupes = RegExp(r'rn|cl|ii|nn|iu|vv');

  /// Fragments sûrs d'une ligne lue (partie médicament : avant la posologie). [masque] : confiance ML Kit.
  static List<FragmentSur> extraire(String texte, {String? masque}) {
    var t = NormalisationProduit.sansAccents(texte);
    var m = masque != null && masque.length == texte.length ? masque : null;
    if (t.length != texte.length) m = null;
    final p = SegmentMedicament.posologie.firstMatch(t);
    if (p != null) {
      t = t.substring(0, p.start);
      if (m != null) m = m.substring(0, p.start);
    }
    final out = <FragmentSur>[];
    final mot = RegExp(r'[a-z]+');
    for (final w in mot.allMatches(t)) {
      final s = w.group(0)!;
      if (s.length < longueurMin || NormalisationProduit.formes.contains(s) || NormalisationProduit.qualificatifsStricts.contains(s)) {
        continue;
      }
      // Positions douteuses : confiance basse, lettres de confusion à plusieurs lettres, groupes ambigus.
      final douteux = List<bool>.filled(s.length, false);
      for (var i = 0; i < s.length; i++) {
        if (_coupures.contains(s[i])) douteux[i] = true;
        if (m != null && m[w.start + i] == '0') douteux[i] = true;
      }
      for (final g in _groupes.allMatches(s)) {
        for (var i = g.start; i < g.end; i++) {
          douteux[i] = true;
        }
      }
      var debut = 0;
      for (var i = 0; i <= s.length; i++) {
        if (i == s.length || douteux[i]) {
          if (i - debut >= longueurMin) {
            final f = s.substring(debut, i);
            out.add(FragmentSur(f, plier(f)));
          }
          debut = i + 1;
        }
      }
    }
    return out;
  }

  /// Forme indexée d'un nom du catalogue : lettres seules, sans accents, pliées.
  static String nomIndexe(String nom) => plier(NormalisationProduit.sansAccents(nom).replaceAll(RegExp(r'[^a-z]'), ''));

  /// Requête serveur « contient » (joker %) : « %frag1%frag2 ».
  static String requeteServeur(List<FragmentSur> f) => f.isEmpty ? '' : '%${f.take(2).map((x) => x.brut).join('%')}';

  /// « …PHOS… …LUFA… ».
  static String indication(Iterable<FragmentSur> f) => f.map((x) => '…${x.brut.toUpperCase()}…').join(' ');
}

/// Index de trigrammes des noms du catalogue (pliés). Construit une fois.
class IndexFragments {
  final List<ProductSearchResult> produits;
  final List<String> noms;
  final Map<int, List<int>> _postings = {};

  IndexFragments(Iterable<ProductSearchResult> source)
      : produits = source.toList(),
        noms = [for (final p in source) FragmentsO3.nomIndexe(p.strNAME)] {
    for (var i = 0; i < noms.length; i++) {
      final n = noms[i];
      final vus = <int>{};
      for (var k = 0; k + 3 <= n.length; k++) {
        final t = _tri(n, k);
        if (vus.add(t)) (_postings[t] ??= []).add(i);
      }
    }
  }

  static int _tri(String s, int k) => (s.codeUnitAt(k) << 16) | (s.codeUnitAt(k + 1) << 8) | s.codeUnitAt(k + 2);

  /// Produits dont le nom (plié) contient [plie].
  List<int> contenant(String plie) {
    if (plie.length < 3) return const [];
    List<int>? plusRare;
    for (var k = 0; k + 3 <= plie.length; k++) {
      final l = _postings[_tri(plie, k)];
      if (l == null) return const [];
      if (plusRare == null || l.length < plusRare.length) plusRare = l;
    }
    return [for (final i in plusRare!) if (noms[i].contains(plie)) i];
  }
}

/// Infos lues sur la ligne utiles au filtrage : dosages, formes, qualificatifs stricts.
class IndicesLigne {
  final Set<String> dosages;
  final bool Function(ProductSearchResult) formeCompatible;
  final bool Function(ProductSearchResult) formeIdentique;
  final bool Function(ProductSearchResult) dosageCommun;
  final bool Function(ProductSearchResult) dosageConnu;
  final bool formeLue;
  const IndicesLigne({
    required this.dosages,
    required this.formeLue,
    required this.formeCompatible,
    required this.formeIdentique,
    required this.dosageCommun,
    required this.dosageConnu,
  });
}

/// Classement par fragments (pur Dart). [bonus] : popularité / apprentissages / stock, 0…0,08.
List<PropositionFragment> classerParFragments({
  required List<FragmentSur> fragments,
  required List<int> Function(String plie) contenant,
  required ProductSearchResult Function(int) produit,
  required String Function(int) nomIndexe,
  required IndicesLigne indices,
  required double Function(ProductSearchResult) bonus,
  Set<String> exclus = const {},
}) {
  if (fragments.isEmpty) return const [];
  final total = fragments.fold<int>(0, (s, f) => s + f.plie.length);
  final parFragment = <int, List<int>>{};
  for (var i = 0; i < fragments.length; i++) {
    var ids = contenant(fragments[i].plie);
    if (ids.length > FragmentsO3.frequenceMax) {
      // Trop fréquent : gardé seulement si le dosage / la forme lus ramènent le choix à 30 produits au plus.
      if (indices.dosages.isEmpty && !indices.formeLue) continue;
      ids = [
        for (final k in ids)
          if ((indices.dosages.isEmpty || indices.dosageCommun(produit(k))) && (!indices.formeLue || indices.formeIdentique(produit(k)))) k,
      ];
      if (ids.length > FragmentsO3.frequenceMax || ids.isEmpty) continue;
    }
    parFragment[i] = ids;
  }
  if (parFragment.isEmpty) return const [];
  final couverts = <int, List<int>>{};
  for (final e in parFragment.entries) {
    for (final k in e.value) {
      (couverts[k] ??= []).add(e.key);
    }
  }
  final out = <PropositionFragment>[];
  for (final e in couverts.entries) {
    final p = produit(e.key);
    if (exclus.contains(p.lgFAMILLEID)) continue;
    final frs = e.value..sort();
    final longueur = frs.fold<int>(0, (s, i) => s + fragments[i].plie.length);
    final couverture = longueur / total;
    if (couverture < 0.5 && longueur < 6) continue;
    // Fragments de 4 lettres seulement : trop courants dans un grand catalogue, sauf confirmés par le dosage lu.
    final plusLong = frs.fold<int>(0, (s, i) => math.max(s, fragments[i].plie.length));
    if (plusLong < 5 && !(indices.dosages.isNotEmpty && indices.dosageCommun(p))) continue;
    var c = 0.45 + 0.3 * couverture;
    // Ordre des fragments respecté dans le nom.
    if (frs.length >= 2) {
      final n = nomIndexe(e.key);
      var pos = -1, ordre = true;
      for (final i in frs) {
        final j = n.indexOf(fragments[i].plie, pos + 1);
        if (j < 0) {
          ordre = false;
          break;
        }
        pos = j;
      }
      if (ordre) c += 0.05;
    }
    if (indices.dosages.isNotEmpty && indices.dosageConnu(p)) {
      if (!indices.dosageCommun(p)) continue; // dosage lu différent : écarté
      c += 0.1;
    }
    if (indices.formeLue) c += indices.formeCompatible(p) ? 0.03 : -0.15;
    c += bonus(p);
    c = math.min(c, FragmentsO3.confianceMax);
    if (c < FragmentsO3.confianceMin) continue;
    out.add(PropositionFragment(p, c, FragmentsO3.indication([for (final i in frs) fragments[i]])));
  }
  out.sort((a, b) {
    final x = b.confiance.compareTo(a.confiance);
    return x != 0 ? x : b.produit.intNUMBERAVAILABLE.compareTo(a.produit.intNUMBERAVAILABLE);
  });
  return out.take(FragmentsO3.maximum).toList();
}
