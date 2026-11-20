// lib/ventes/reedition/reedition_ventes.dart
// 5.4.0 — Réédition des ventes (retour du pharmacien du 20/11 : « permettre de rééditer les ventes (comptant,
// assurance, carnet) effectuées sur chaque terminal »). Lecture seule côté serveur.
//
// Liste : GET v1/ventestats (SalesStatsRessource.getAlls, « Ventes terminées » du web ; serveur déployé 76aa5fc1)
//   ?start&limit&query&dtStart=AAAA-MM-JJ&dtEnd&hStart=00:00&hEnd=23:59[&lgTypeVenteId=1|2|3]
//   → {total, data:[VenteDTO : lgPREENREGISTREMENTID, strREF, strREFTICKET, intPRICE, intCUSTPART, dtUPDATED
//      (JJ/MM/AAAA), heure (HH:mm), strTYPEVENTE (VNO/VO), lgTYPEVENTEID (1 comptant, 2 assurance, 3 carnet),
//      cancel, posteSaisie, posteEncaissement, clientFullName…]}
//   Ventes clôturées seulement (statut is_Closed), triées par date croissante côté serveur (relues ici de la plus
//   récente à la plus ancienne). `query` cherche le début du n° de ticket, de la référence ou d'un produit.
//   Droits : ceux du serveur, inchangés — sans « Afficher les ventes de tous les utilisateurs » (str_SHOW_VENTE)
//   l'utilisateur ne voit que SES ventes ; sans P_SHOW_ALL_ACTIVITY, celles de son emplacement seulement.
// Ce terminal : vente notée par l'application à sa clôture (VentesDuTerminal) OU poste de saisie / d'encaissement
// égal au nom de cet appareil (en-tête X-Poste). « Tous les postes » : tout ce que le serveur montre au compte.
//
// Réimpression : même rendu que l'original — ticket dessiné par le serveur (route image vno / vo, celle de
// l'impression après la vente) ; serveur sans la route (404 / 405) : gabarit local reconstruit avec la vente relue
// (GET ventestats/{id} et ses lignes). Nombre d'exemplaires choisi, pause « Ticket suivant (i/N) » entre deux.
// Le serveur n'a pas de mention « DUPLICATA » sur ces tickets (ni la route image ni la réimpression du poste) :
// rien n'est ajouté par l'application.
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

/// Filtre de type de vente.
enum TypeReedition {
  tous('Toutes', null),
  comptant('Comptant', '1'),
  assurance('Assurance', '2'),
  carnet('Carnet', '3');

  final String libelle;

  /// lg_TYPE_VENTE_ID du serveur (filtre `lgTypeVenteId`).
  final String? lgTypeVenteId;
  const TypeReedition(this.libelle, this.lgTypeVenteId);
}

/// Une vente terminée lue sur le serveur (affichage seulement : rien n'est gardé sur l'appareil).
class VenteTerminee {
  final String id;
  final String reference;
  final String numeroTicket;
  final String lgTypeVenteId;
  final String typeVente;
  final DateTime? date;
  final int montant;
  final int partClient;
  final String client;
  final String posteSaisie;
  final String posteEncaissement;
  final bool annulee;

  const VenteTerminee({
    required this.id,
    required this.reference,
    required this.numeroTicket,
    required this.lgTypeVenteId,
    required this.typeVente,
    required this.date,
    required this.montant,
    required this.partClient,
    required this.client,
    required this.posteSaisie,
    required this.posteEncaissement,
    required this.annulee,
  });

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()) ?? 0;
  static String _s(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s == 'null' ? '' : s;
  }

  static DateTime? _date(String jour, String heure) {
    try {
      return DateFormat('dd/MM/yyyy HH:mm').parseStrict('$jour ${heure.isEmpty ? '00:00' : heure.substring(0, heure.length.clamp(0, 5))}');
    } catch (_) {
      return null;
    }
  }

  static VenteTerminee? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _s(j['lgPREENREGISTREMENTID']);
    if (id.isEmpty) return null;
    final c = j['cancel'];
    return VenteTerminee(
      id: id,
      reference: _s(j['strREF']),
      numeroTicket: _s(j['strREFTICKET']),
      lgTypeVenteId: _s(j['lgTYPEVENTEID']),
      typeVente: _s(j['strTYPEVENTE']).toUpperCase(),
      date: _date(_s(j['dtUPDATED']), _s(j['heure'])),
      montant: _int(j['intPRICE']),
      partClient: _int(j['intCUSTPART']),
      client: _s(j['clientFullName']),
      posteSaisie: _s(j['posteSaisie']),
      posteEncaissement: _s(j['posteEncaissement']),
      annulee: c == true || c == 'true',
    );
  }

  /// Comptant (route image vno) ; sinon assurance, carnet ou dépôt (route image vo).
  bool get comptant => typeVente == 'VNO' || (typeVente.isEmpty && lgTypeVenteId == '1');

  /// Type de la route image du serveur.
  String get typeImage => comptant ? 'vno' : 'vo';

  TypeReedition get categorie => switch (lgTypeVenteId) {
        '3' => TypeReedition.carnet,
        '2' => TypeReedition.assurance,
        _ => comptant ? TypeReedition.comptant : TypeReedition.assurance,
      };

  /// Numéro montré et cherché : n° de ticket, sinon la référence.
  String get numero => numeroTicket.isNotEmpty ? numeroTicket : reference;

  /// Vente de ce terminal : notée à sa clôture, ou poste du serveur égal au nom de l'appareil.
  bool deCeTerminal({required bool Function(String id) notee, required String? nomPoste}) {
    if (notee(id)) return true;
    final n = (nomPoste ?? '').trim();
    return n.isNotEmpty && (posteSaisie == n || posteEncaissement == n);
  }

  /// Recherche locale : début ou partie du n° de ticket ou de la référence (chiffres seulement comparés aussi).
  bool correspond(String recherche) {
    final q = recherche.trim().toUpperCase();
    if (q.isEmpty) return true;
    return numeroTicket.toUpperCase().contains(q) || reference.toUpperCase().contains(q);
  }
}

/// Réponse de la liste.
sealed class ResultatListeVentes {
  const ResultatListeVentes();
}

class ListeVentes extends ResultatListeVentes {
  final List<VenteTerminee> ventes;

  /// Le serveur en a plus que ce qui a été lu (au-delà de [ReeditionVentesService.maxLues]).
  final bool tronquee;
  const ListeVentes(this.ventes, {this.tronquee = false});
}

class EchecListeVentes extends ResultatListeVentes {
  final String message;
  const EchecListeVentes(this.message);
}

class ReeditionVentesService {
  final Dio dio;
  ReeditionVentesService(this.dio);

  static const int parPage = 200;

  /// Ventes lues au plus pour une journée (les plus récentes).
  static const int maxLues = 1000;

  static const String messageReseau = 'Serveur injoignable : liste des ventes non chargée. Vérifiez le réseau, puis réessayez.';
  static const String messageSession = 'Session expirée : reconnectez-vous pour voir les ventes.';

  Map<String, dynamic> _params(DateTime jour, TypeReedition type, String recherche, int start, int limit) {
    final d = DateFormat('yyyy-MM-dd').format(jour);
    return {
      'start': start,
      'limit': limit,
      'query': recherche.trim(),
      'dtStart': d,
      'dtEnd': d,
      'hStart': '00:00',
      'hEnd': '23:59',
      if (type.lgTypeVenteId != null) 'lgTypeVenteId': type.lgTypeVenteId,
    };
  }

  Future<(int, List<VenteTerminee>)?> _page(Map<String, dynamic> p) async {
    final r = await dio.get('/ventestats', queryParameters: p);
    final b = r.data;
    if (b is! Map || b['data'] is! List) return null;
    final total = int.tryParse('${b['total'] ?? ''}') ?? (b['data'] as List).length;
    return (total, (b['data'] as List).map(VenteTerminee.fromJson).whereType<VenteTerminee>().toList());
  }

  /// Ventes terminées du [jour] (les plus récentes d'abord).
  Future<ResultatListeVentes> lister({required DateTime jour, TypeReedition type = TypeReedition.tous, String recherche = ''}) async {
    try {
      final premiere = await _page(_params(jour, type, recherche, 0, parPage));
      if (premiere == null) return const EchecListeVentes('Réponse du serveur illisible : liste des ventes non chargée.');
      final (total, l) = premiere;
      final ventes = [...l];
      // Les pages suivantes, en partant des plus récentes (le serveur trie par date croissante).
      var tronquee = false;
      if (total > ventes.length) {
        var debut = ventes.length;
        if (total > maxLues) {
          // Journée très chargée : les [maxLues] plus récentes seulement (la 1ʳᵉ page lue est la plus ancienne).
          ventes.clear();
          debut = total - maxLues;
          tronquee = true;
        }
        for (var s = debut; s < total; s += parPage) {
          final p = await _page(_params(jour, type, recherche, s, parPage));
          if (p == null) break;
          ventes.addAll(p.$2);
        }
      }
      final vus = <String>{};
      final uniques = [for (final v in ventes) if (vus.add(v.id)) v];
      uniques.sort((a, b) {
        final da = a.date, db = b.date;
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
      return ListeVentes(uniques, tronquee: tronquee);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 401) return const EchecListeVentes(messageSession);
      if (code >= 400) return EchecListeVentes('Refus du serveur (code $code) : liste des ventes non chargée.');
      return const EchecListeVentes(messageReseau);
    } catch (_) {
      return const EchecListeVentes('Réponse du serveur illisible : liste des ventes non chargée.');
    }
  }
}
