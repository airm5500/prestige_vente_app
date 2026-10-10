// lib/parametres/parametres_logic.dart
// Réglages : contrôles de saisie (serveur), résumés des rubriques et recherche.
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class ParametresChecks {
  ParametresChecks._();

  static final _ipLike = RegExp(r'^[0-9.]+$');
  static final _hostName =
      RegExp(r'^(?=.{1,253}$)[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$');

  static bool isIpv4(String v) {
    final parts = v.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) return false;
      final n = int.tryParse(p);
      if (n == null || n > 255) return false;
    }
    return true;
  }

  /// Adresse IP v4 (ex. 192.168.1.20). Un nom de serveur (ex. pharmacie.ddns.net) reste accepté
  /// pour ne pas bloquer une configuration existante ; une suite de chiffres doit être une IP valide.
  static String? host(String? value, {required bool required}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return required ? 'Ce champ est requis' : null;
    if (_ipLike.hasMatch(v)) return isIpv4(v) ? null : 'Format invalide (ex. 192.168.1.20)';
    return _hostName.hasMatch(v) ? null : 'Format invalide (ex. 192.168.1.20)';
  }

  static String? port(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ce champ est requis';
    final n = RegExp(r'^\d{1,5}$').hasMatch(v) ? int.tryParse(v) : null;
    if (n == null || n < 1 || n > 65535) return 'Port de 1 à 65535';
    return null;
  }

  static String? appName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Ce champ est requis';
    if (v.length > 60) return 'Nom trop long';
    if (RegExp(r'[\s/\\?#%:@]').hasMatch(v)) return 'Sans espace ni / ? # % : @';
    return null;
  }
}

/// Rubriques de la page d'entrée des réglages.
enum Rubrique { connexion, ventes, impression, stock, apparence, equipe, securite, licence }

extension RubriqueInfo on Rubrique {
  String get title => switch (this) {
        Rubrique.connexion => 'Connexion au serveur',
        Rubrique.ventes => 'Ventes',
        Rubrique.impression => 'Impression',
        Rubrique.stock => 'Stock & contrôles',
        Rubrique.apparence => 'Apparence',
        Rubrique.equipe => 'Équipe & pointage',
        Rubrique.securite => 'Sécurité',
        Rubrique.licence => 'Licence & appareil',
      };

  /// Protégée par le code administrateur (décision Q7).
  bool get locked => switch (this) {
        Rubrique.connexion || Rubrique.ventes || Rubrique.stock || Rubrique.equipe || Rubrique.securite => true,
        _ => false,
      };

  /// Mots recherchés en plus du titre et du résumé.
  String get keywords => switch (this) {
        Rubrique.connexion => 'serveur ip adresse locale distante port application nom test ping connexion réseau wifi',
        Rubrique.ventes => 'version ventes nouvelle ancienne paiement modes qr code wave orange mtn moov carte '
            'tiers payants assurance rv masquer produits',
        Rubrique.impression => 'ticket imprimante largeur 58 80 mm mode test aperçu qr code-barres code barres '
            'nombre tickets assurance essai sunmi',
        Rubrique.stock => 'contrôle livraison pointage bl comparaison stock théorique machine réception '
            'péremption courte validation entrée',
        Rubrique.apparence => 'présentation tableau de bord compact guidé a b c accueil organiser menu interface '
            'nouvel accueil version recherche commence par contient début milieu nom',
        Rubrique.equipe => 'pointage employés badge nfc empreinte pin rapport diagnostic lecteur',
        Rubrique.securite => 'code pin administrateur admin mot de passe sécurité',
        Rubrique.licence => 'licence expiration jours appareil modèle android identifiant support',
      };
}

/// Recherche sans accents ni majuscules.
String normalise(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

bool rubriqueMatches(Rubrique r, String summary, String query) {
  final q = normalise(query.trim());
  if (q.isEmpty) return true;
  final text = normalise('${r.title} $summary ${r.keywords}');
  return q.split(RegExp(r'\s+')).every(text.contains);
}

/// Recherche dans un texte libre (ex. « Se déconnecter »).
bool rubriqueMatchesText(String text, String query) {
  final q = normalise(query.trim());
  if (q.isEmpty) return true;
  final t = normalise(text);
  return q.split(RegExp(r'\s+')).every(t.contains);
}

String presentationShort(ListPresentation p) => switch (p) {
      ListPresentation.dashboard => 'A',
      ListPresentation.compact => 'B',
      ListPresentation.guided => 'C',
    };

class ParametresSummary {
  ParametresSummary._();

  static String connexion(SettingsProvider s) {
    final ip = s.localIp.isEmpty ? 'IP non renseignée' : '${s.localIp}:${s.port}';
    return '$ip · ${s.appName}${s.remoteIp.isEmpty ? '' : ' · IP distante'}';
  }

  static String ventes(SettingsProvider s, {required bool newSales}) {
    final n = s.enabledPaymentMethodIds.length;
    return '${newSales ? 'Nouvelle version' : 'Ancienne version'} · $n mode${n > 1 ? 's' : ''} de paiement'
        ' · ${s.maxTiersPayants} tiers payant${s.maxTiersPayants > 1 ? 's' : ''} max';
  }

  static String impression(SettingsProvider s) {
    final code = s.ticketCodeType == 'BARCODE' ? 'code-barres' : 'QR code';
    return '${s.paperWidth} mm · ${s.numberOfTickets} ticket${s.numberOfTickets > 1 ? 's' : ''} · $code'
        '${s.isTestPrintMode ? ' · mode test' : ''}';
  }

  static String stock(SettingsProvider s) =>
      'Comparaison ${s.blStockComparisonMode == 'machine' ? 'machine' : 'théorique'}'
      '${!s.canEditDeliveryControl || !s.canEditBlControl ? ' · modification limitée' : ''}';

  /// La recherche n'est mentionnée que si elle n'est plus « commence par » (réglage par défaut).
  static String apparence(ListPresentation p, {SearchMode search = SearchMode.commencePar}) =>
      'Présentation ${presentationShort(p)} · organiser l\'accueil'
      '${search == SearchMode.contient ? ' · recherche « contient »' : ''}';

  static String licence(LicenceProvider l) {
    switch (l.status) {
      case LicenceStatus.valid:
        final d = l.remainingDays;
        return 'Valide · $d jour${d > 1 ? 's' : ''}';
      case LicenceStatus.expired:
        return 'Expirée';
      case LicenceStatus.none:
        return 'Aucune licence enregistrée';
      case LicenceStatus.error:
        return 'Non vérifiée (${l.errorTitle.toLowerCase()})';
      case LicenceStatus.loading:
        return l.licence == null ? 'Non vérifiée' : 'Vérification…';
    }
  }
}
