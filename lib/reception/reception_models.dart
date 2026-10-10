// lib/reception/reception_models.dart
// Réception d'un BL sur mobile : bons à entrer en stock, commandes, lignes et lots saisis.
import 'package:intl/intl.dart';

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(dynamic v) => v == null ? '' : '$v';

/// Découpe "A | B | C" (format renvoyé par le serveur pour les lots et dates d'une ligne).
List<String> splitPipes(String v) => v.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// BL créé, en attente d'entrée en stock (statut serveur "enable").
class ReceptionBl {
  final String id;
  final String ref;
  final String grossiste;
  final String grossisteId;
  final String date;
  final String orderRef;
  final int lines;
  final int boxes;
  final int amount;
  final bool directImport;

  /// false : le paramètre « date de péremption obligatoire » est actif sur Prestige.
  final bool peremptionOptional;

  const ReceptionBl({
    required this.id,
    required this.ref,
    this.grossiste = '',
    this.grossisteId = '',
    this.date = '',
    this.orderRef = '',
    this.lines = 0,
    this.boxes = 0,
    this.amount = 0,
    this.directImport = false,
    this.peremptionOptional = true,
  });

  factory ReceptionBl.fromJson(Map<String, dynamic> j) => ReceptionBl(
        id: _str(j['lg_BON_LIVRAISON_ID']),
        ref: _str(j['str_REF_LIVRAISON']),
        grossiste: _str(j['str_GROSSISTE_LIBELLE']),
        grossisteId: _str(j['lg_GROSSISTE_ID']),
        date: _str(j['dt_DATE_LIVRAISON']),
        orderRef: _str(j['str_REF_ORDER']),
        lines: _int(j['int_NBRE_LIGNE_BL_DETAIL']),
        boxes: _int(j['int_NBRE_PRODUIT']),
        amount: _int(j['PRIX_ACHAT_TOTAL']),
        directImport: j['directImport'] == true,
        peremptionOptional: j['DISPLAYFILTER'] != false,
      );
}

/// Commande en cours ou passée, à transformer en BL.
class ReceptionOrder {
  final String id;
  final String ref;
  final String grossiste;
  final String date;
  final int products;
  final int amount;
  final String statut;

  const ReceptionOrder({
    required this.id,
    required this.ref,
    this.grossiste = '',
    this.date = '',
    this.products = 0,
    this.amount = 0,
    this.statut = '',
  });

  bool get passed => statut == 'passed';
  String get statutLabel => switch (statut) {
        'passed' => 'Passée',
        'pharma' => 'PharmaML',
        _ => 'En cours',
      };

  factory ReceptionOrder.fromJson(Map<String, dynamic> j) => ReceptionOrder(
        id: _str(j['lg_ORDER_ID']),
        ref: _str(j['str_REF_ORDER']),
        grossiste: _str(j['str_GROSSISTE_LIBELLE']),
        date: _str(j['dt_CREATED']),
        products: _int(j['int_NBRE_PRODUIT']),
        amount: _int(j['PRIX_ACHAT_TOTAL']),
        statut: _str(j['str_STATUT']),
      );
}

/// Ligne d'un BL, avec les lots déjà saisis (par cet appareil ou un autre).
class ReceptionLine {
  final String detailId;
  final String produitId;
  final String name;

  /// CIP (ou code article du grossiste, selon Prestige).
  final String code;
  final int ordered;

  /// Somme des lots déjà saisis (boîtes, UG comprises).
  final int entered;
  final int freeQty;
  final List<String> lots;
  final List<DateTime> expiries;
  final String blRef;
  final int stock;
  final String location;

  const ReceptionLine({
    required this.detailId,
    required this.produitId,
    required this.name,
    this.code = '',
    required this.ordered,
    this.entered = 0,
    this.freeQty = 0,
    this.lots = const [],
    this.expiries = const [],
    this.blRef = '',
    this.stock = 0,
    this.location = '',
  });

  /// Même règle que Prestige : la somme des lots (UG comprises) est comparée à la quantité commandée.
  int get remaining => ordered - entered < 0 ? 0 : ordered - entered;
  bool get isEmpty => entered == 0;
  bool get isComplete => entered >= ordered;
  bool get isPartial => !isEmpty && !isComplete;

  static final _fmt = DateFormat('dd/MM/yyyy');

  factory ReceptionLine.fromJson(Map<String, dynamic> j) => ReceptionLine(
        detailId: _str(j['lg_BON_LIVRAISON_DETAIL']),
        produitId: _str(j['lg_FAMILLE_ID']),
        name: _str(j['lg_FAMILLE_NAME']),
        code: _str(j['lg_FAMILLE_CIP']),
        ordered: _int(j['int_QTE_CMDE']),
        entered: _int(j['quantiteSaisie']),
        freeQty: _int(j['freeQty']),
        lots: splitPipes(_str(j['lots'])),
        expiries: [
          for (final d in splitPipes(_str(j['datePeremption'])))
            if (_tryParse(d) != null) _tryParse(d)!,
        ],
        blRef: _str(j['str_REF_LIVRAISON']),
        stock: _int(j['lg_FAMILLE_QTE_STOCK']),
        location: _str(j['lg_ZONE_GEO_NAME']),
      );

  static DateTime? _tryParse(String d) {
    try {
      return _fmt.parseStrict(d);
    } catch (_) {
      return null;
    }
  }
}

/// Résultat d'une opération serveur (succès + message à afficher).
class ReceptionResult {
  final bool success;
  final String message;
  final Map<String, dynamic> data;

  const ReceptionResult(this.success, [this.message = '', this.data = const {}]);
}
