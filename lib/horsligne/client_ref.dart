// lib/horsligne/client_ref.dart
// H4 — clé client anti-doublon (patch serveur docs/serveur/H4_client_ref.patch).
//
// Chaque création envoyée depuis la file hors ligne (1ʳᵉ ligne d'une vente, création d'un retour
// fournisseur) porte l'en-tête HTTP `X-Client-Ref` (identifiant local, stable entre deux envois).
// Un serveur avec le patch H4 ne crée jamais deux fois pour la même clé (il renvoie la réponse de la
// création initiale) et permet de relire la création : GET /app-vente/client-ref/{ref} (ancien préfixe /mobile/ :
// premières versions du patch ; préfixe détecté par routes_app_vente.dart).
// Un serveur sans le patch ignore l'en-tête : l'appli garde alors exactement son fonctionnement
// d'origine (anomalie « vérifiez sur Prestige » si la réponse de la création est perdue).
//
// La capacité du serveur (GET /app-vente/capacites, repli /mobile/capacites → `clientRef: true`) est lue AVANT l'envoi de la
// création et mise en cache par adresse de serveur (nouveau serveur = nouvelle vérification ; oui gardé
// 30 min, non gardé 5 min, réponse indéterminée jamais gardée).
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';

/// En-tête HTTP de la clé client.
const String enteteClientRef = 'X-Client-Ref';

/// Clé client d'une vente hors ligne (identifiant local, préfixé pour la reconnaître sur le serveur).
String cleClientVente(String venteLocaleId) => 'HL2-$venteLocaleId';

/// Création relue sur le serveur par sa clé.
class ClientRefInfo {
  /// 'VENTE' ou 'RETOUR_FRS'.
  final String type;
  final String id;
  final String? reference;
  final String? statut;

  /// L'objet créé existe encore sur le serveur.
  final bool existe;
  const ClientRefInfo({required this.type, required this.id, this.reference, this.statut, this.existe = true});

  static const typeVente = 'VENTE';
  static const typeRetour = 'RETOUR_FRS';
}

/// Capacité H4 du serveur, mise en cache par adresse.
abstract final class CapaciteClientRef {
  static final Map<String, ({bool ok, DateTime at})> _cache = {};
  static DateTime Function() clock = DateTime.now;

  /// [lire] : true / false si le serveur a répondu clairement, null si indéterminé (réseau, session).
  static Future<bool> verifier(String serveur, Future<bool?> Function() lire) async {
    final c = _cache[serveur];
    if (c != null && clock().difference(c.at) < (c.ok ? const Duration(minutes: 30) : const Duration(minutes: 5))) return c.ok;
    bool? r;
    try {
      r = await lire();
    } catch (_) {
      r = null;
    }
    if (r == null) return false;
    _cache[serveur] = (ok: r, at: clock());
    return r;
  }

  /// Oublie tout (changement de serveur, tests).
  static void vider() => _cache.clear();

  /// Lecture de GET …/capacites (RoutesAppVente.lireCapacites). 404, ou 401 « expire » (repli sur v1/mobile/, API à
  /// jeton d'un serveur sans H4) = non.
  static bool? depuisReponse(int status, dynamic body) {
    if (status == 200 && body is Map) return body['clientRef'] == true;
    if (status == 404) return false;
    if (status == 401 && body is Map && body.containsKey('expire')) return false;
    return null;
  }
}

/// Lecture de GET /app-vente/client-ref/{ref} (ou /mobile/…) : info, null = clé inconnue (création jamais faite), échec sinon.
VenteResult<ClientRefInfo?> clientRefDepuisReponse(int status, dynamic body) {
  if (status == 200 && body is Map && body['success'] == true && '${body['id'] ?? ''}'.isNotEmpty) {
    String? s(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
    return VenteOk(ClientRefInfo(
      type: '${body['type'] ?? ''}',
      id: '${body['id']}',
      reference: s(body['reference']),
      statut: s(body['statut']),
      existe: body['existe'] != false,
    ));
  }
  if (status == 404 && body is Map && body['success'] == false) return const VenteOk(null);
  if (status == 401 || status == 403) return const VenteFailed('Session expirée : reconnectez-vous puis relancez l\'envoi.');
  return VenteFailed('Relecture de la création impossible (code $status).');
}

/// Accès H4 d'une passerelle de vente (implémenté par DioVenteGateway ; facultatif : sans lui, H2 inchangé).
abstract interface class ClientRefGateway {
  /// Le serveur gère `X-Client-Ref` (cache par serveur).
  Future<bool> clientRefSupporte();

  /// Relit une création par sa clé.
  Future<VenteResult<ClientRefInfo?>> lireClientRef(String ref);

  /// Même passerelle, dont les créations de vente (1ᵉʳ article) portent l'en-tête `X-Client-Ref: ref`.
  VenteGateway avecClientRef(String ref);
}
