// lib/ordonnances/o3/correspondance_o3.dart
// Étape O3 : correspondance catalogue améliorée. Pour chaque ligne lue, le produit le plus proche du
// CATALOGUE (copie locale complète si disponible, sinon recherche serveur existante) :
// - nom : distance d'édition pondérée sur les confusions de l'écriture + phonétique française, début de mot
//   (abréviations : « pediat » → PÉDIATRIQUE), deux premiers mots collés (« Bio Ritmo » = BIORITMO) ;
// - dosage (1 g ≠ 500 mg) et forme (cp, gél, sp/susp, amp, suppo, sol, collyre, inj, sachet…) discriminants ;
// - qualificatifs (Plus, Pro, Forte, T, AB…) ;
// - bonus produits en stock et produits réellement vendus (point d'accroche [PopulariteProduits]).
// Renvoie les 3 meilleures propositions avec une confiance 0…1 ; sous [seuilSur] la ligne est « à vérifier ».
// Le pharmacien choisit / valide toujours : rien n'est ajouté au panier sans sa validation.
import 'dart:math' as math;

import 'package:prestige_vente_app/api/models/product.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/normalisation_produit.dart';
import 'package:prestige_vente_app/ordonnances/o3/similarite.dart';
import 'package:prestige_vente_app/services/prescription_parser.dart';
import 'package:prestige_vente_app/ventes/core/product_lookup.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// Nombre de ventes connues par produit (bonus « réellement vendu »). Point d'accroche : compteur local
/// des produits validés sur ordonnance aujourd'hui, historique de ventes du serveur demain.
abstract class PopulariteProduits {
  int ventes(String produitId);
}

class AucunePopularite implements PopulariteProduits {
  const AucunePopularite();
  @override
  int ventes(String produitId) => 0;
}

class PopulariteMemoire implements PopulariteProduits {
  final Map<String, int> compteurs;
  const PopulariteMemoire(this.compteurs);
  @override
  int ventes(String produitId) => compteurs[produitId] ?? 0;
}

/// Une proposition pour une ligne.
class PropositionO3 {
  final ProductSearchResult produit;

  /// Confiance 0…1.
  final double confiance;
  const PropositionO3(this.produit, this.confiance);

  @override
  String toString() => '${produit.strNAME} (${(confiance * 100).round()} %)';
}

/// Résultat pour une ligne : 3 propositions au plus, la première est retenue si elle dépasse [CorrespondanceO3.seuilProposition].
class ResultatO3 {
  final List<PropositionO3> propositions;

  /// Panne de la recherche (≠ introuvable).
  final String? panne;
  const ResultatO3(this.propositions, {this.panne});

  PropositionO3? get meilleure => propositions.isEmpty ? null : propositions.first;

  /// Proposition sûre : au-dessus de [CorrespondanceO3.seuilSur] et nettement devant la suivante.
  bool get sur {
    final m = meilleure;
    if (m == null || m.confiance < CorrespondanceO3.seuilSur) return false;
    return propositions.length < 2 || m.confiance - propositions[1].confiance >= 0.05;
  }
}

/// Lecture analysée (ligne d'ordonnance ou nom du catalogue).
class _Analyse {
  final List<String> mots;
  final String phon0;
  final Set<String> dosages;
  final Set<String> formes;
  final Set<String> stricts;
  final Set<String> souples;
  _Analyse(this.mots, this.dosages, this.formes, this.stricts, this.souples) : phon0 = mots.isEmpty ? '' : Similarite.phonetique(mots.first);

  /// Mots de marque candidats d'une LECTURE : 2 premiers mots et leur concaténation (1ᵉʳ mot parasite possible ;
  /// concaténation seulement de deux vrais mots).
  List<String> get marques => [
        if (mots.isNotEmpty) mots[0],
        if (mots.length >= 2) mots[1],
        if (mots.length >= 2 && mots[0].length >= 3 && mots[1].length >= 3) mots[0] + mots[1],
      ];

  /// Mots de marque d'un PRODUIT : 1ᵉʳ mot et 2 premiers mots collés (« BIO RITMO » = « bioritmo »).
  List<String> get marquesProduit => [
        if (mots.isNotEmpty) mots[0],
        if (mots.length >= 2) mots[0] + mots[1],
      ];
}

/// Lettres présentes (masque 26 bits) : filtre rapide avant la distance d'édition.
int _masque(String s) {
  var m = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i) - 97;
    if (c >= 0 && c < 26) m |= 1 << c;
  }
  return m;
}

int _bits(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

class _Entree {
  final ProductSearchResult produit;
  final _Analyse a;
  final List<String> marques;
  final List<String> phons;
  final List<int> masques;
  _Entree(this.produit, this.a)
      : marques = a.marquesProduit,
        phons = [for (final m in a.marquesProduit) Similarite.phonetique(m)],
        masques = [for (final m in a.marquesProduit) _masque(m)];
}

class CorrespondanceO3 {
  /// En dessous : aucune proposition retenue (la ligne reste « non trouvée », alternatives consultables).
  static const double seuilProposition = 0.65;

  /// Une ligne de plus de [motsMax] mots est une phrase (en-tête, mention), pas un médicament.
  static const int motsMax = 5;

  /// Au-dessus (et nettement devant la 2ᵉ) : proposition sûre ; sinon « à vérifier ».
  static const double seuilSur = 0.80;

  final PopulariteProduits popularite;
  final List<_Entree>? _index;
  final ProductPageSearch? _recherche;

  CorrespondanceO3._(this._index, this._recherche, this.popularite);

  /// Catalogue complet en mémoire (copie locale) : index construit une fois.
  factory CorrespondanceO3.catalogue(Iterable<ProductSearchResult> produits, {PopulariteProduits popularite = const AucunePopularite()}) =>
      CorrespondanceO3._([for (final p in produits) _Entree(p, _analyser(p.strNAME))], null, popularite);

  /// Sans copie locale : candidats obtenus par la recherche serveur existante (préfixes du nom lu).
  factory CorrespondanceO3.recherche(ProductPageSearch recherche, {PopulariteProduits popularite = const AucunePopularite()}) =>
      CorrespondanceO3._(null, recherche, popularite);

  /// Copie locale si elle contient des produits ([chargerTout] renvoie la liste complète), sinon recherche serveur.
  static Future<CorrespondanceO3> auto(
    ProductPageSearch recherche, {
    Future<List<ProductSearchResult>> Function()? chargerTout,
    PopulariteProduits popularite = const AucunePopularite(),
  }) async {
    if (chargerTout != null) {
      try {
        final tout = await chargerTout();
        if (tout.isNotEmpty) return CorrespondanceO3.catalogue(tout, popularite: popularite);
      } catch (_) {}
    }
    return CorrespondanceO3.recherche(recherche, popularite: popularite);
  }

  int get tailleIndex => _index?.length ?? 0;

  // ---------------------------------------------------------------------------
  // Analyse des noms
  // ---------------------------------------------------------------------------
  static const _formesCanon = <String, String>{
    'cp': 'cp', 'cps': 'cp', 'cpr': 'cp', 'cpm': 'cp', 'comp': 'cp', 'comprime': 'cp', 'comprimes': 'cp', 'lyoc': 'cp',
    'orodispersible': 'cp', 'gel': 'gel', 'gelule': 'gel', 'gelules': 'gel', 'gels': 'gel', 'caps': 'gel',
    'capsule': 'gel', 'capsules': 'gel', 'sp': 'liq', 'sirop': 'liq', 'sir': 'liq', 'susp': 'liq',
    'suspension': 'liq', 'buv': 'liq', 'buvable': 'liq', 'buvale': 'liq', 'sol': 'liq', 'solution': 'liq',
    'amp': 'amp', 'ampoule': 'amp', 'ampoules': 'amp', 'inj': 'inj', 'injectable': 'inj', 'injection': 'inj',
    'perf': 'inj', 'suppo': 'suppo', 'suppos': 'suppo', 'suppositoire': 'suppo', 'suppositoires': 'suppo',
    'supp': 'suppo', 'coll': 'coll', 'collyre': 'coll', 'sach': 'sach', 'sachet': 'sach', 'sachets': 'sach',
    'pdre': 'sach', 'poudre': 'sach', 'pom': 'pom', 'pommade': 'pom', 'pde': 'pom', 'creme': 'pom', 'spray': 'spray',
    'aerosol': 'spray', 'pulv': 'spray', 'nasal': 'spray', 'eff': 'eff', 'effv': 'eff', 'effervescent': 'eff',
  };

  static bool _formesCompatibles(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return true;
    for (final x in a) {
      for (final y in b) {
        if (x == y) return true;
        final p = {x, y};
        if (p.containsAll(const {'cp', 'eff'}) || p.containsAll(const {'amp', 'liq'}) || p.containsAll(const {'liq', 'sach'})) {
          return true;
        }
      }
    }
    return false;
  }

  static const _souplesComplets = <String>['pediatrique', 'nourrisson', 'enfant', 'junior', 'retard'];

  static _Analyse _analyser(String texte) {
    final n = NormalisationProduit.normaliser(texte);
    final brut = NormalisationProduit.sansAccents(texte).split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty);
    final formes = <String>{for (final t in brut) if (_formesCanon.containsKey(t)) _formesCanon[t]!};
    final stricts = NormalisationProduit.stricts(n);
    final souples = n.qualificatifs.difference(NormalisationProduit.qualificatifsStricts)..remove('lp');
    final mots = <String>[];
    for (final m in n.mots) {
      // Abréviation d'un qualificatif (« pediat », « nourr ») : qualificatif, pas un mot du nom.
      final q = m.length >= 4 ? _souplesComplets.where((s) => s.startsWith(m)).firstOrNull : null;
      if (q != null && mots.isNotEmpty) {
        souples.add(q);
      } else {
        mots.add(m);
      }
    }
    return _Analyse(mots, n.dosages, formes, stricts, souples);
  }

  // ---------------------------------------------------------------------------
  // Score
  // ---------------------------------------------------------------------------
  static double _marque(_Analyse q, List<String> phonsQ, List<int> masquesQ, _Entree e) {
    var best = 0.0;
    final qm = q.marques, pm = e.marques;
    for (var i = 0; i < qm.length; i++) {
      final a = qm[i];
      if (a.length < 3) continue;
      final ma = masquesQ[i], na = _bits(ma);
      for (var j = 0; j < pm.length; j++) {
        final b = pm[j];
        final phon = phonsQ[i].isNotEmpty && phonsQ[i] == e.phons[j];
        // Filtres rapides : longueur et lettres communes (le mot lu peut être tronqué : « pediat »).
        if (!phon) {
          if (b.length < a.length * 0.6 || (b.length > a.length * 1.7 && a.length < 4)) continue;
          if (_bits(ma & e.masques[j]) < na * 0.5) continue;
        }
        var s = Similarite.ressemblanceDebut(a, b);
        if (phon && a.length >= 4) s = math.max(s, 0.92);
        // Mots courts : presque identiques seulement (« are » ≠ PARA, « aln » ≠ ALM) ; deux mots collés : proches.
        if (a.length < 5 && s < 0.9) continue;
        if (b.length < 4 && s < 1) continue;
        if (i == 2 && s < 0.85) continue;
        // Le 2ᵉ mot seul de la lecture vaut un peu moins (1ᵉʳ mot parasite).
        if (i == 1) s *= 0.92;
        if (s > best) best = s;
      }
    }
    return best;
  }

  /// Score brut (peut dépasser 1 : sert au classement ; la confiance affichée est bornée à 0…1).
  double _score(_Analyse q, List<String> phonsQ, List<int> masquesQ, _Entree e) {
    final m = _marque(q, phonsQ, masquesQ, e);
    if (m < 0.62) return 0;
    var s = m;
    // Dosage
    final dq = q.dosages, dp = e.a.dosages;
    if (dq.isNotEmpty && dp.isNotEmpty) {
      s += dq.intersection(dp).isNotEmpty ? 0.10 : -0.35;
    } else if (dq.isNotEmpty) {
      s -= 0.03;
    }
    // Forme
    if (q.formes.isNotEmpty && e.a.formes.isNotEmpty) s += _formesCompatibles(q.formes, e.a.formes) ? 0.04 : -0.15;
    // Qualificatifs
    final sq = q.stricts, sp = e.a.stricts;
    if (sq.length != sp.length || !sq.containsAll(sp)) s -= 0.25;
    for (final x in q.souples) {
      s += e.a.souples.contains(x) ? 0.05 : -0.15;
    }
    // Stock et ventes
    if (e.produit.intNUMBERAVAILABLE > 0) s += 0.02;
    final v = popularite.ventes(e.produit.lgFAMILLEID);
    if (v > 0) s += 0.06 * math.min(1.0, math.log(1 + v) / math.log(20));
    // Nom lu nettement déformé : jamais « sûr », quel que soit le dosage (le pharmacien vérifie).
    if (m < 0.85) s = math.min(s, seuilSur - 0.01);
    return s;
  }

  List<PropositionO3> _classer(_Analyse q, Iterable<_Entree> entrees, int n) {
    final phonsQ = [for (final m in q.marques) Similarite.phonetique(m)];
    final masquesQ = [for (final m in q.marques) _masque(m)];
    final scores = <(ProductSearchResult, double)>[];
    for (final e in entrees) {
      final s = _score(q, phonsQ, masquesQ, e);
      if (s > 0) scores.add((e.produit, s));
    }
    scores.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : b.$1.intNUMBERAVAILABLE.compareTo(a.$1.intNUMBERAVAILABLE);
    });
    final vus = <String>{};
    return [
      for (final p in scores)
        if (vus.add(p.$1.lgFAMILLEID)) PropositionO3(p.$1, p.$2.clamp(0.0, 1.0)),
    ].take(n).toList();
  }

  /// Propositions pour un nom lu (synchrone, catalogue en mémoire).
  List<PropositionO3> proposerTexte(String texte, {int n = 3}) {
    final q = _analyser(texte);
    if (q.mots.isEmpty || q.mots.every((m) => m.length < 3) || q.mots.length > motsMax) return const [];
    return _classer(q, _index ?? const [], n);
  }

  /// Propositions pour une ligne : top [n] avec confiance. Les propositions sous [seuilProposition] sont écartées.
  Future<ResultatO3> proposer(PrescriptionLine ligne, {int n = 3}) async {
    final texte = ligne.text.trim().isEmpty ? ligne.query : ligne.text;
    final q = _analyser(texte);
    if (q.mots.isEmpty || q.mots.every((m) => m.length < 3) || q.mots.length > motsMax) return const ResultatO3([]);
    final index = _index;
    if (index != null) {
      return ResultatO3(_classer(q, index, n).where((p) => p.confiance >= seuilProposition).toList());
    }
    final (candidats, panne) = await _candidatsServeur(q);
    final props = _classer(q, [for (final p in candidats) _Entree(p, _analyser(p.strNAME))], n);
    return ResultatO3(props.where((p) => p.confiance >= seuilProposition).toList(), panne: candidats.isEmpty ? panne : null);
  }

  /// Sans copie locale : produits commençant comme les mots lus (3 puis 2 premières lettres), 200 au plus par requête.
  Future<(List<ProductSearchResult>, String?)> _candidatsServeur(_Analyse q) async {
    final recherche = _recherche!;
    final requetes = <String>{
      for (final m in q.marques.take(2))
        if (m.length >= 3) ...[m.substring(0, 3), m.substring(0, 2)],
    };
    final out = <String, ProductSearchResult>{};
    String? panne;
    for (final r in requetes) {
      var start = 0;
      while (start < 200) {
        final page = await recherche(r, start, ProductLookup.pageSize);
        if (page is! VenteOk<ProductPage>) {
          panne = page.message;
          break;
        }
        for (final p in page.value.items) {
          out[p.lgFAMILLEID] = p;
        }
        start += page.value.items.length;
        if (page.value.items.length < ProductLookup.pageSize || start >= page.value.total) break;
      }
    }
    return (out.values.toList(), panne);
  }
}
