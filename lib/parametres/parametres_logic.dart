// lib/parametres/parametres_logic.dart
// Réglages : contrôles de saisie (serveur), résumés des rubriques et recherche.
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

class ParametresChecks {
  ParametresChecks._();

  static bool isIpv4(String v) => AdresseServeur.estIpv4(v);

  /// Adresse IP v4 (ex. 192.168.1.20) ou nom de serveur (ex. pharmacie.ddns.net), avec « https:// » et un port
  /// (« :8443 ») facultatifs (4.1.0) ; une suite de chiffres doit être une IP valide.
  static String? host(String? value, {required bool required}) => AdresseServeur.erreur(value, requis: required);

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
enum Rubrique { connexion, ventes, impression, stock, apparence, equipe, securite, licence, horsLigne, borne, images, paiementsMobile }

extension RubriqueInfo on Rubrique {
  String get title => switch (this) {
        Rubrique.connexion => 'Connexion au serveur',
        Rubrique.ventes => 'Ventes',
        Rubrique.impression => 'Impression',
        Rubrique.stock => 'Stock & contrôles',
        Rubrique.horsLigne => 'Hors ligne',
        Rubrique.apparence => 'Apparence',
        Rubrique.equipe => 'Équipe & pointage',
        Rubrique.securite => 'Sécurité',
        Rubrique.licence => 'Licence & appareil',
        Rubrique.borne => 'Borne libre-service',
        Rubrique.images => 'Images des produits',
        Rubrique.paiementsMobile => 'Paiements mobile money',
      };

  /// Protégée par le code administrateur (décision Q7).
  bool get locked => switch (this) {
        Rubrique.connexion || Rubrique.ventes || Rubrique.stock || Rubrique.equipe || Rubrique.securite || Rubrique.borne || Rubrique.images || Rubrique.paiementsMobile => true,
        _ => false,
      };

  /// Mots recherchés en plus du titre et du résumé.
  String get keywords => switch (this) {
        Rubrique.connexion => 'serveur ip adresse locale distante port application nom test ping connexion réseau wifi',
        Rubrique.ventes => 'version ventes nouvelle ancienne paiement modes qr code wave orange mtn moov carte '
            'tiers payants assurance rv masquer produits ordonnance banc essai lecture',
        Rubrique.impression => 'ticket imprimante largeur 58 80 mm mode test aperçu qr code-barres code barres '
            'nombre tickets assurance essai sunmi prévente prevente produits afficher masquer',
        Rubrique.stock => 'contrôle livraison pointage bl comparaison stock théorique machine réception '
            'péremption courte validation entrée',
        Rubrique.horsLigne => 'hors ligne coupure panne serveur injoignable réseau copie locale catalogue synchro '
            'mise à jour produits clients vider',
        Rubrique.apparence => 'présentation tableau de bord compact guidé a b c accueil organiser menu interface '
            'nouvel accueil version recherche commence par contient début milieu nom '
            'taille écran affichage très compact petit écran sunmi v2s',
        Rubrique.equipe => 'pointage employés badge nfc empreinte pin rapport diagnostic lecteur',
        Rubrique.securite => 'code pin administrateur admin mot de passe sécurité connexion rapide qui etes vous terminal partage '
            'rester connecte pin personnel assistance numero telephone appeler',
        Rubrique.licence => 'licence expiration jours appareil modèle android identifiant support '
            'nom de cet appareil poste caisse terminal ventes terminées',
        Rubrique.borne => 'borne libre service self kiosque client vitrine liste guidee ticket discret inactivite '
            'categories produits mis en avant epinglage ecran',
        Rubrique.images => 'images photos produits vignettes cache telechargement prechargement hors ligne photo appareil',
        Rubrique.paiementsMobile => 'mobile money wave orange mtn moov qr agregateur cinetpay paiement automatique notifications historique',
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
    final ip = s.localIp.isEmpty ? 'IP non renseignée' : s.adresseAffichee(false);
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
        '${s.afficherProduitsPrevente ? ' · produits sur la prévente' : ''}'
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
