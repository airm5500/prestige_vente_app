// lib/services/ticket_texte.dart
// 4.14.0 — Ticket de VENTE local (comptant, assurance, carnet) mis en page COMME LE SERVEUR (demande du pharmacien du
// 19/11/2026 : « ticket assurance désordonné, le prix passe sur 2 lignes, trop d'écart avec le nom du produit ; même
// présentation que le serveur »).
//
// Cause du ticket désordonné (photo du 19/11, terminal Sunmi 58 mm) : la largeur réglée était 80 mm. Le ticket était
// alors composé pour 48 caractères (colonnes 26 + 10 + 10) et l'imprimante intégrée de 58 mm, qui n'en imprime que
// 32, coupait chaque ligne au 32e caractère : « Qte*P. » / « U Total », « 1*1 50 » tout à droite puis « 0 » et
// « 1 500 » à la ligne, traits sur deux lignes. Corrections :
//  - la largeur de l'imprimante intégrée est lue sur l'imprimante (58 mm imposé sur le terminal), le réglage ne sert
//    qu'à une imprimante sans largeur connue (lib/services/largeur_ticket.dart) ;
//  - chaque ligne est composée ici à la largeur exacte (32 ou 48 caractères), jamais plus : un montant ne passe
//    jamais à la ligne, une désignation longue passe à la ligne aux espaces (comme RenduTicket du serveur) ;
//  - seuls des caractères d'une colonne : espace insécable des milliers (« 1 500 » de intl) → espace, « × » → « x ».
//
// Ordre des blocs du serveur (rest/service/ticket/TicketDocument.ORDRE, ConversionTicket) : ENTETE (officine),
// PHARMACIEN, TITRE, INTERVENANTS (vendeur), CLIENT (client, matricule, bénéficiaire, bon, part du client, organismes
// avec leur taux), CORPS (désignation, puis « quantité x prix » à gauche et le montant à droite sur UNE ligne), RECAP
// (« 2 lignes · 3 articles »), TOTAUX (Total avant remise, « * » remise, « Pris sur le carnet » / « Vente à terme »),
// NET (« NET » en 58 mm, « NET À PAYER » en 80 mm, en grand), REGLEMENT, PIED (date, code, référence).
//
// Le serveur dessinera le ticket lui-même (GET v1/vente/ticket/{type}/{id}/image, lib/services/ticket_serveur.dart) :
// ce gabarit local ne sert qu'aux serveurs sans cette route (officine non mise à jour) et aux ventes hors ligne.
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/utils/constants.dart';

/// Une ligne du ticket, composée à la largeur : [texte] tient TOUJOURS en [colonnes] caractères (ou en
/// [colonnesGrand] pour une ligne [grand]). [code] : emplacement du QR code / code-barres (texte vide).
class LigneTicket {
  /// Texte (sans les espaces du centrage pour une ligne [centre]).
  final String texte;
  final bool gras;
  final bool grand;
  final bool code;

  /// Ligne centrée : les espaces sont ajoutés à l'impression ([imprimee]).
  final bool centre;
  const LigneTicket(this.texte, {this.gras = false, this.grand = false, this.centre = false}) : code = false;
  const LigneTicket.code() : texte = '', gras = false, grand = false, centre = false, code = true;

  /// Texte tel qu'imprimé sur [largeur] caractères (centrage compris), jamais plus long que [largeur].
  String imprimee(int largeur) => centre && texte.length < largeur ? (' ' * ((largeur - texte.length) ~/ 2)) + texte : texte;

  @override
  String toString() => texte;
}

/// Ticket composé : lignes dans l'ordre d'impression.
class TicketTexte {
  final int colonnes;
  final List<LigneTicket> lignes;
  /// Donnée du QR code / code-barres (vide : pas de code).
  final String codeDonnees;
  const TicketTexte({required this.colonnes, required this.lignes, this.codeDonnees = ''});

  /// Caractères par ligne en police normale : 32 en 58 mm, 48 en 80 mm (police 12 × 24 points).
  static int colonnesPour(int papierMm) => papierMm <= 58 ? 32 : 48;

  /// Caractères par ligne en grand (police 36 points, 18 points par caractère) : 21 en 58 mm, 32 en 80 mm.
  static int colonnesGrandPour(int papierMm) => papierMm <= 58 ? 21 : 32;

  int get colonnesGrand => colonnes <= 32 ? 21 : 32;

  /// Lignes telles qu'imprimées (centrage compris) ; « [CODE] » à la place du code.
  List<String> get imprimees => [for (final l in lignes) l.code ? '[CODE]' : l.imprimee(l.grand ? colonnesGrand : colonnes)];

  /// Texte brut (aperçu, tests, captures) : une ligne par élément.
  String get texte => imprimees.join('\n');
}

/// Article d'un ticket.
typedef ArticleTicket = ({String designation, int quantite, int prixUnitaire, int montant});

/// Ligne « libellé : valeur » d'un bloc.
typedef PaireTicket = ({String libelle, String valeur});

/// Mise en page à largeur fixe, règles du rendu du serveur.
class MiseEnPageTicket {
  final int colonnes;
  final bool court;
  MiseEnPageTicket(int papierMm)
      : colonnes = TicketTexte.colonnesPour(papierMm),
        court = papierMm <= 58;

  int get colonnesGrand => court ? 21 : 32;

  /// Texte d'une colonne par caractère : espaces insécables → espace, « × » → « x », « − » → « - »,
  /// « · » → « - », retours à la ligne → espace, autres signes hors Latin-1 → « ? ».
  static String propre(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      switch (r) {
        case 0x00A0:
        case 0x202F:
        case 0x2007:
        case 0x2009:
        case 0x0A:
        case 0x0D:
        case 0x09:
          b.write(' ');
        case 0x00D7:
          b.write('x');
        case 0x2212:
        case 0x2013:
        case 0x2014:
        case 0x00B7:
          b.write('-');
        case 0x2019:
        case 0x2018:
          b.write("'");
        default:
          b.write(r >= 0x20 && r <= 0xFF ? String.fromCharCode(r) : '?');
      }
    }
    return b.toString();
  }

  /// Montant « 1 500 » (espace simple des milliers).
  static String nombre(int v) => propre(Constants.formatNumber(v));

  /// Montant avec l'unité, comme le serveur : « 1 500 F » en 58 mm, « 1 500 F CFA » en 80 mm.
  String montantF(int v) => '${nombre(v)}${court ? ' F' : ' F CFA'}';

  /// Coupe [texte] aux espaces en lignes de [largeur] caractères au plus (un mot plus long est coupé lui-même).
  static List<String> couper(String texte, int largeur) {
    final t = propre(texte).trim().replaceAll(RegExp(r' +'), ' ');
    if (t.isEmpty) return const [];
    if (largeur < 1) return [t];
    final out = <String>[];
    var courante = '';
    for (var mot in t.split(' ')) {
      while (mot.length > largeur) {
        if (courante.isNotEmpty) {
          out.add(courante);
          courante = '';
        }
        out.add(mot.substring(0, largeur));
        mot = mot.substring(largeur);
      }
      if (mot.isEmpty) continue;
      if (courante.isEmpty) {
        courante = mot;
      } else if (courante.length + 1 + mot.length <= largeur) {
        courante = '$courante $mot';
      } else {
        out.add(courante);
        courante = mot;
      }
    }
    if (courante.isNotEmpty) out.add(courante);
    return out;
  }

  /// Texte centré sur [largeur] (coupé aux espaces si besoin).
  static List<String> centre(String texte, int largeur) => [
        for (final l in couper(texte, largeur)) (' ' * ((largeur - l.length) ~/ 2)) + l,
      ];

  /// Libellé à gauche (coupé au besoin), valeur à droite sur la DERNIÈRE ligne du libellé (comme RenduTicket.paire).
  /// La valeur ne passe jamais à la ligne ; si elle est plus large que la ligne, elle seule est gardée, à droite.
  static List<String> paire(String libelle, String valeur, int largeur) {
    final v = propre(valeur).trim();
    if (v.length >= largeur) return [v.substring(v.length - largeur)];
    final place = largeur - v.length - 1;
    final l = couper(libelle, place);
    if (l.isEmpty) return [v.padLeft(largeur)];
    return [
      for (var i = 0; i < l.length - 1; i++) l[i],
      l.last.padRight(largeur - v.length) + v,
    ];
  }

  String trait() => '-' * colonnes;
}

/// Composition des tickets de vente (comptant, assurance, carnet) à la manière du serveur.
class TicketVenteTexte {
  TicketVenteTexte._();

  /// Ticket de vente encaissée.
  /// [titre] : « VENTE ASSURANCE », « VENTE CARNET », « VENTE » (comptant) ; [clients] : lignes du bloc CLIENT
  /// (dans l'ordre du serveur) ; [remise] : montant de la remise (0 = aucune ligne) ; [aTerme] : montant pris par
  /// les organismes (« Pris sur le carnet » / « Vente à terme ») ou null ; [reglement] : lignes du règlement.
  static TicketTexte vente({
    required int papierMm,
    required String officine,
    String pharmacien = '',
    required String titre,
    String? provisoire,
    String provisoireNote = '',
    required String vendeur,
    List<PaireTicket> clients = const [],
    required List<ArticleTicket> articles,
    required int total,
    int remise = 0,
    ({String libelle, int montant})? aTerme,
    required int net,
    List<PaireTicket> reglement = const [],
    PaireTicket? monnaie,
    required DateTime date,
    String reference = '',
    bool code = false,
  }) {
    final m = MiseEnPageTicket(papierMm);
    final c = m.colonnes;
    final lignes = <LigneTicket>[];
    void ajouter(Iterable<String> l, {bool gras = false, bool grand = false}) {
      for (final x in l) {
        lignes.add(LigneTicket(x, gras: gras, grand: grand));
      }
    }

    void centrer(String t, {bool gras = false, bool grand = false}) {
      for (final x in MiseEnPageTicket.couper(t, grand ? m.colonnesGrand : c)) {
        lignes.add(LigneTicket(x, gras: gras, grand: grand, centre: true));
      }
    }

    // ENTETE · PHARMACIEN
    centrer(officine.toUpperCase(), gras: true, grand: true);
    centrer(pharmacien);
    // TITRE (trait fin au-dessus, comme le serveur)
    ajouter([m.trait()]);
    centrer(titre, gras: true);
    if (provisoire != null) {
      centrer(provisoire, gras: true);
      if (provisoireNote.isNotEmpty) centrer(provisoireNote);
    }
    // INTERVENANTS
    if (vendeur.trim().isNotEmpty) ajouter(MiseEnPageTicket.couper('Vendeur : $vendeur', c));
    // CLIENT
    if (clients.isNotEmpty) {
      ajouter([m.trait()]);
      for (final p in clients) {
        if (p.valeur.trim().isEmpty) {
          // Nom (client, bénéficiaire) : sur ses lignes, jamais poussé à droite.
          ajouter(MiseEnPageTicket.couper(p.libelle, c));
        } else {
          ajouter(MiseEnPageTicket.paire('${p.libelle.replaceAll(RegExp(r'\s*:+\s*$'), '')} :', p.valeur, c));
        }
      }
    }
    // CORPS
    ajouter([m.trait()]);
    var quantites = 0;
    for (final a in articles) {
      ajouter(MiseEnPageTicket.couper(a.designation, c), gras: true);
      ajouter(MiseEnPageTicket.paire('${a.quantite} x ${MiseEnPageTicket.nombre(a.prixUnitaire)}', MiseEnPageTicket.nombre(a.montant), c));
      quantites += a.quantite.abs();
    }
    ajouter([m.trait()]);
    // RECAP
    if (articles.isNotEmpty) {
      final n = articles.length;
      ajouter(MiseEnPageTicket.couper('$n ligne${n > 1 ? 's' : ''} - $quantites article${quantites > 1 ? 's' : ''}', c));
    }
    // TOTAUX : « Total » seulement s'il apprend quelque chose (remise ou part des organismes), comme le serveur.
    // « Total » : toujours (le ticket du mobile l'imprimait déjà : « Total » / « Total Brut ») ; le serveur ne l'imprime
    // que s'il apprend quelque chose (remise, part des organismes).
    ajouter(MiseEnPageTicket.paire('Total', m.montantF(total), c));
    if (remise > 0) ajouter(MiseEnPageTicket.paire('*', '- ${m.montantF(remise)}', c));
    if (aTerme != null) ajouter(MiseEnPageTicket.paire(aTerme.libelle, m.montantF(aTerme.montant), c), gras: true);
    // NET (en grand)
    ajouter(MiseEnPageTicket.paire(m.court ? 'NET' : 'NET À PAYER', '${MiseEnPageTicket.nombre(net)} F CFA', m.colonnesGrand),
        gras: true, grand: true);
    // REGLEMENT
    for (final p in reglement) {
      ajouter(MiseEnPageTicket.paire(p.libelle, p.valeur, c));
    }
    if (monnaie != null) ajouter(MiseEnPageTicket.paire(monnaie.libelle, monnaie.valeur, c), gras: true);
    // PIED
    ajouter([m.trait()]);
    centrer(DateFormat(m.court ? 'dd/MM/yy HH:mm' : 'dd/MM/yyyy HH:mm').format(date));
    if (code && reference.isNotEmpty) lignes.add(const LigneTicket.code());
    if (reference.isNotEmpty) centrer(reference);
    return TicketTexte(colonnes: c, lignes: lignes, codeDonnees: code ? reference : '');
  }

  /// Lignes du règlement (un ou plusieurs modes), comme le bloc REGLEMENT du serveur.
  static ({List<PaireTicket> lignes, PaireTicket? monnaie}) reglement({
    required MiseEnPageTicket m,
    String mode = '',
    int? montantVerse,
    int? monnaie,
    List<({String mode, int montant, int? recu, int? rendu})>? reglements,
  }) {
    final l = <PaireTicket>[];
    PaireTicket? rendu;
    if (reglements != null && reglements.isNotEmpty) {
      for (final r in reglements) {
        l.add((libelle: r.mode.toUpperCase(), valeur: m.montantF(r.montant)));
        if (r.recu != null) {
          l.add((libelle: 'Espèces versées', valeur: m.montantF(r.recu!)));
          rendu = (libelle: 'Monnaie rendue', valeur: m.montantF(r.rendu ?? 0));
        }
      }
      return (lignes: l, monnaie: rendu);
    }
    if (mode.trim().isNotEmpty) l.add((libelle: 'Règlement', valeur: mode.toUpperCase()));
    if (montantVerse != null) {
      final especes = mode.trim().toLowerCase().startsWith('esp');
      l.add((libelle: especes ? 'Espèces versées' : 'Montant versé', valeur: m.montantF(montantVerse)));
    }
    if (monnaie != null && monnaie > 0) rendu = (libelle: 'Monnaie rendue', valeur: m.montantF(monnaie));
    return (lignes: l, monnaie: rendu);
  }
}
