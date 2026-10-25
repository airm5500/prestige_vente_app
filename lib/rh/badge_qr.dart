// lib/rh/badge_qr.dart
// 4.6.2 — QR des badges RH imprimés par Prestige depuis le 16/10 (serveur : util.BadgeQr, RhBadgeService) :
//   PRESTIGE-BADGE|1|<numéro>|<login>|<secret>
// Le terminal de pointage n'a besoin que du NUMÉRO (comparé au champ `badge` de l'employé, comme un code-barres).
// Le LOGIN et le SECRET ne sont jamais gardés, affichés, journalisés ni envoyés : ce fichier ne les renvoie pas, et
// une lecture refusée n'en dit que la raison (jamais le contenu lu).
//
// Douchette restée en clavier américain (QWERTY) sur un appareil en AZERTY (retours du 23 et du 24/10, serveur
// 0f909974 et 81cc8c54) : « PRESTIGE-BADGE|1|… » arrive en « PRESTIGE)BQDGEµ&µ… » ; avec le verrouillage des
// majuscules, en « PRESTIGE°BQDGE*1*… ». Le contenu est remis tel qu'imprimé, avec les mêmes tables que le serveur.

/// Préfixe du contenu du QR d'un badge RH.
const String prefixeBadgeQr = 'PRESTIGE-BADGE';

/// Seule version connue du contenu.
const String versionBadgeQr = '1';

// Tables de util.BadgeQr (serveur) : caractère US du QR ↔ caractère reçu sur un appareil AZERTY.
const String _toucheUs = '1234567890-_|aqzwmAQZWM';
const String _toucheFr = '&é"\'(-è_çà)°µqawz,QAWZ?';
const String _prefixeQwerty = 'PRESTIGE)BQDGE';
const String _toucheUsMaj = '-_|aqzwmAQZWM';
const String _toucheFrMaj = '°)*qawz,QAWZ?';
const String _prefixeQwertyMaj = 'PRESTIGE°BQDGE';

/// Lecture d'un QR de badge.
sealed class LectureBadgeQr {
  const LectureBadgeQr();
}

/// QR reconnu : [numero] du badge (le login et le secret ne sont pas gardés).
class BadgeQrReconnu extends LectureBadgeQr {
  final String numero;
  const BadgeQrReconnu(this.numero);
}

/// QR de badge illisible (version inconnue, lecture déformée, numéro vide) : [raison] seulement, jamais le contenu.
class BadgeQrIllisible extends LectureBadgeQr {
  final String raison;
  const BadgeQrIllisible(this.raison);
}

String _sansControle(String s) => s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();

/// Vrai si la lecture COMMENCE comme un QR de badge (même incomplète, déformée par la douchette ou en minuscules) :
/// le champ de saisie la masque aussitôt et elle n'est jamais affichée.
bool ressembleBadgeQr(String lu) => _sansControle(lu).toUpperCase().startsWith('PRESTIGE');

/// Contenu lu par une douchette en QWERTY sur un appareil AZERTY, remis tel qu'imprimé (comme BadgeQr.depuisQwerty).
String depuisQwerty(String lu) {
  final maj = lu.startsWith(_prefixeQwertyMaj);
  final fr = maj ? _toucheFrMaj : _toucheFr;
  final us = maj ? _toucheUsMaj : _toucheUs;
  final sb = StringBuffer();
  for (final c in lu.split('')) {
    final i = fr.indexOf(c);
    sb.write(i < 0 ? c : us[i]);
  }
  return sb.toString();
}

/// QR de badge → numéro ; null si la lecture n'est pas un QR de badge (code-barres, NFC, saisie : inchangés).
LectureBadgeQr? lireBadgeQr(String lu) {
  var v = _sansControle(lu);
  if (!v.toUpperCase().startsWith('PRESTIGE')) return null;
  if (v.startsWith(_prefixeQwertyMaj) || v.startsWith(_prefixeQwerty)) v = depuisQwerty(v);
  final p = v.split('|');
  if (p.first.toUpperCase() != prefixeBadgeQr) {
    return const BadgeQrIllisible('lecture déformée : vérifiez le réglage du lecteur de badge');
  }
  if (p.length < 5) return const BadgeQrIllisible('lecture incomplète du QR du badge');
  if (p[1] != versionBadgeQr) return const BadgeQrIllisible('QR de badge d\'une version inconnue');
  final numero = p[2].trim();
  // Numéro d'un badge Prestige : lettres, chiffres et tirets (RhBadgeService).
  if (numero.isEmpty || !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(numero)) {
    return const BadgeQrIllisible('numéro du badge illisible dans le QR');
  }
  return BadgeQrReconnu(numero);
}
