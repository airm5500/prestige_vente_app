// lib/services/saisie_peremption.dart
// Saisie manuelle d'une date de péremption — UNE seule règle pour toute l'application (4.11.0, plan du pharmacien du
// 08/11 : « date de péremption ne pas être obligé de mettre les barres ; 0128 = 01/01/2028 ; 010128 = 01/01/2028 ;
// cas déjà traité dans la mise à jour péremption, la saisie de date y est parfaitement gérée »).
// C'est la règle de « Mise à jour péremption » (ExpirationUpdateScreen._formatAndValidateDate), sortie ici pour être
// partagée, et non recopiée, par « Mise à jour péremption » et la réception des BL :
//   - séparateurs facultatifs (/ - . espace) ;
//   - 4 chiffres MMAA       → 01/MM/20AA   (0128 → 01/01/2028) ;
//   - 6 chiffres JJMMAA     → JJ/MM/20AA   (010128 → 01/01/2028) ;
//   - 8 chiffres JJMMAAAA   → JJ/MM/AAAA ;
//   - avec séparateurs : J/M/AA ou JJ/MM/AAAA (jour et mois sur 1 ou 2 chiffres), M/AA ou MM/AAAA (1er du mois).
// Une date impossible (31/02, mois 13…) est refusée (null), jamais « corrigée » en une autre date.
import 'package:intl/intl.dart';

final _affichage = DateFormat('dd/MM/yyyy');

/// Date lue dans [saisie], ou null si elle est illisible ou impossible.
DateTime? lireDatePeremption(String saisie) {
  final t = saisie.trim();
  if (t.isEmpty) return null;
  int an(String a) => a.length == 2 ? 2000 + int.parse(a) : int.parse(a);
  DateTime? date(int a, int m, int j) {
    if (m < 1 || m > 12 || j < 1 || j > 31) return null;
    final d = DateTime(a, m, j);
    return d.month == m && d.day == j ? d : null;
  }

  // Avec séparateurs : chaque partie peut faire 1 ou 2 chiffres.
  final parties = t.split(RegExp(r'[\/\-\.\s]+'));
  if (parties.length > 1) {
    if (parties.any((p) => !RegExp(r'^\d+$').hasMatch(p))) return null;
    if (parties.length == 3 && parties[0].length <= 2 && parties[1].length <= 2 && (parties[2].length == 2 || parties[2].length == 4)) {
      return date(an(parties[2]), int.parse(parties[1]), int.parse(parties[0]));
    }
    if (parties.length == 2 && parties[0].length <= 2 && (parties[1].length == 2 || parties[1].length == 4)) {
      return date(an(parties[1]), int.parse(parties[0]), 1);
    }
    return null;
  }
  // Sans séparateur : règle de « Mise à jour péremption ».
  if (!RegExp(r'^\d+$').hasMatch(t)) return null;
  return switch (t.length) {
    4 => date(2000 + int.parse(t.substring(2, 4)), int.parse(t.substring(0, 2)), 1),
    6 => date(2000 + int.parse(t.substring(4, 6)), int.parse(t.substring(2, 4)), int.parse(t.substring(0, 2))),
    8 => date(int.parse(t.substring(4, 8)), int.parse(t.substring(2, 4)), int.parse(t.substring(0, 2))),
    _ => null,
  };
}

/// Affichage JJ/MM/AAAA d'une date de péremption.
String formaterDatePeremption(DateTime d) => _affichage.format(d);

/// Aide affichée sous le champ.
const aideSaisiePeremption = 'Sans barres : 0128 = 01/01/2028, 010128 = 01/01/2028';
