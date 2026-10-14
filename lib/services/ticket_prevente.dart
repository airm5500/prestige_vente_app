// lib/services/ticket_prevente.dart
// 4.1.1 — Lignes produits des tickets de PRÉVENTE (texte à largeur fixe, police monospace de l'imprimante Sunmi :
// 32 caractères en 58 mm, 48 en 80 mm). Utilisées par :
//  - le ticket de prévente du comptoir (comptant, assurance, carnet) quand le réglage
//    « Afficher les produits sur le ticket de prévente » est activé (Réglages › Impression) ;
//  - le ticket de la borne (hors « ticket discret », réglage propre à la borne).
// Les tickets de VENTE encaissée gardent leur propre mise en page (receipt_service.dart), inchangée.
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/utils/constants.dart';

class TicketPrevente {
  TicketPrevente._();

  /// Réglage « Afficher les produits sur le ticket de prévente » : mêmes textes dans les deux interfaces
  /// (Réglages › Impression et Configuration d'origine).
  static const String libelleReglage = 'Afficher les produits sur le ticket de prévente';
  static const String aideReglage = 'Comptoir (comptant, assurance, carnet) : nom, quantité et prix de chaque produit. '
      'Désactivé : référence, total et code seulement. La borne garde son propre réglage « Ticket discret ».';

  /// Caractères par ligne selon la largeur du papier (58 mm : 32, sinon 48), comme les autres tickets.
  static int colonnes(int largeurPapier) => largeurPapier == 58 ? 32 : 48;

  /// Nombre maximal de lignes pour le nom d'un produit.
  static const int lignesNom = 2;

  /// Nom du produit sur une ligne s'il tient (complété par des espaces, comme avant), sinon sur DEUX lignes :
  /// coupure à un espace (un mot n'est coupé que s'il est plus long que la ligne). Au-delà de deux lignes, la
  /// fin est remplacée par « .. » (le ticket signale que le nom est raccourci).
  static List<String> nom(String nomProduit, int cols) {
    final t = nomProduit.replaceAll('\n', ' ');
    if (t.length <= cols) return [t.padRight(cols)];
    final mots = t.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    final lignes = <String>[];
    var courante = '';
    var i = 0;
    while (i < mots.length && lignes.length < lignesNom) {
      final m = mots[i];
      if (courante.isEmpty) {
        if (m.length > cols) {
          // Mot plus long que la ligne : coupé, la suite continue sur la ligne suivante.
          lignes.add(m.substring(0, cols));
          mots[i] = m.substring(cols);
          continue;
        }
        courante = m;
        i++;
      } else if (courante.length + 1 + m.length <= cols) {
        courante = '$courante $m';
        i++;
      } else {
        lignes.add(courante);
        courante = '';
      }
    }
    if (courante.isNotEmpty && lignes.length < lignesNom) lignes.add(courante);
    if (i < mots.length) {
      // Reste du nom au-delà de deux lignes : « .. » en fin de 2e ligne.
      final last = lignes.removeLast();
      lignes.add(last.length <= cols - 2 ? '$last..' : '${last.substring(0, cols - 2)}..');
    }
    return [for (final l in lignes) l.padRight(cols)];
  }

  /// Montant d'une ligne (quantité × prix unitaire si le serveur n'a pas donné le total de la ligne).
  static int montantLigne(SaleItemDetail l) => l.intPRICE == 0 ? l.intQUANTITY * l.intPRICEUNITAIR : l.intPRICE;

  /// Lignes d'un produit : nom (1 ou 2 lignes) puis « 2 x 1 200        2 400 » aligné à droite.
  static List<String> produit(SaleItemDetail l, int cols) {
    final px = '${l.intQUANTITY} x ${Constants.formatNumber(l.intPRICEUNITAIR)}';
    final tot = Constants.formatNumber(montantLigne(l));
    return [...nom(l.strNAME, cols), '  $px${tot.padLeft(cols - 2 - px.length)}'];
  }

  /// Toutes les lignes produits.
  static List<String> produits(List<SaleItemDetail> lignes, int cols) => [for (final l in lignes) ...produit(l, cols)];

  /// Nombre d'articles (somme des quantités).
  static int nombreArticles(List<SaleItemDetail> lignes) => lignes.fold<int>(0, (s, l) => s + l.intQUANTITY);

  /// Lignes à imprimer (réimpression) : chargées seulement si le réglage est activé ([afficher]) ; en cas d'échec,
  /// liste vide (le ticket est alors imprimé comme d'origine, sans produits). Réglage désactivé : aucune requête.
  static Future<List<SaleItemDetail>> chargerProduits(bool afficher, Future<List<SaleItemDetail>> Function() charger) async {
    if (!afficher) return const [];
    try {
      return await charger();
    } catch (_) {
      return const [];
    }
  }

  /// Lignes réellement imprimables (les lignes sans nom ni quantité, ajoutées pour porter la référence, sont ignorées).
  static List<SaleItemDetail> imprimables(List<SaleItemDetail> lignes) =>
      [for (final l in lignes) if (l.strNAME.trim().isNotEmpty && l.intQUANTITY > 0) l];

  /// « 1 article » / « 6 articles ».
  static String articles(int n) => '$n article${n > 1 ? 's' : ''}';
}
