// lib/borne/borne_diagnostic.dart
// « Tester la borne » (Réglages › Borne libre-service, 4.1.2) : retour du pharmacien « activée sur un téléphone,
// elle n'affiche pas les données ». Le test dit POURQUOI, étape par étape, sans ouvrir la borne :
//   1. mode borne sur cet appareil ; 2. utilisateur borne renseigné ; 3. mot de passe enregistré (stockage sûr) ;
//   4. connexion de l'utilisateur borne au serveur (refusée ≠ serveur injoignable) ;
//   5. recherche de produits avec la session de la borne (1re catégorie, sinon « DOLI ») ;
//   6. produits mis en avant trouvés.
// La connexion d'essai passe par un client HTTP À PART (son propre pot à cookies) : la session de l'appli (compte
// administrateur qui fait le test) n'est pas touchée. Session d'essai fermée à la fin (POST /user/logout).
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/serveur/panne_serveur.dart';

enum EtatEtapeBorne { ok, attention, echec }

class EtapeBorne {
  final String titre;
  final EtatEtapeBorne etat;
  final String detail;
  const EtapeBorne(this.titre, this.etat, this.detail);

  @override
  String toString() => '$titre : ${etat.name} — $detail';
}

/// Résultat du test : étapes et conclusion.
class DiagnosticBorne {
  final List<EtapeBorne> etapes;
  const DiagnosticBorne(this.etapes);

  bool get ok => etapes.every((e) => e.etat != EtatEtapeBorne.echec);

  String get conclusion => ok
      ? 'La borne est prête : elle se connecte et trouve des produits.'
      : etapes.firstWhere((e) => e.etat == EtatEtapeBorne.echec).detail;
}

/// Exécute le test contre le serveur [baseUrl] (adresse de l'appli, …/prestige/api/v1).
class TesteurBorne {
  final String baseUrl;
  final BorneSecrets secrets;
  final Duration delai;

  /// Client HTTP du test (remplaçable dans les tests) ; par défaut un client neuf, cookies à part.
  final Dio Function(String baseUrl)? client;

  TesteurBorne({required this.baseUrl, BorneSecrets? secrets, this.delai = const Duration(seconds: 15), this.client})
      : secrets = secrets ?? BorneReglages.secrets;

  Dio _nouveauClient() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: delai, receiveTimeout: delai, validateStatus: (_) => true));
    dio.interceptors.add(CookieManager(CookieJar()));
    return dio;
  }

  /// 4.3.3 : aucune réponse (délai, réseau, PC serveur éteint) → « Serveur injoignable… ».
  static String _reseau(DioException e) => switch (e.type) {
        DioExceptionType.badCertificate => 'Certificat du serveur refusé (HTTPS). Vérifiez l\'adresse du serveur.',
        _ => '${MessagesServeur.injoignable} (Réglages › Connexion : adresse du serveur.)',
      };

  Future<DiagnosticBorne> tester(BorneConfig c) async {
    final etapes = <EtapeBorne>[];
    etapes.add(c.actif
        ? const EtapeBorne('Mode borne', EtatEtapeBorne.ok, 'Actif sur cet appareil : la borne s\'ouvre au démarrage.')
        : const EtapeBorne('Mode borne', EtatEtapeBorne.attention,
            'Désactivé sur cet appareil (le test vérifie quand même la connexion et les produits).'));
    if (c.login.trim().isEmpty) {
      etapes.add(const EtapeBorne('Utilisateur borne', EtatEtapeBorne.echec,
          'Utilisateur borne non configuré : renseignez le login Prestige de la borne, puis Enregistrer.'));
      return DiagnosticBorne(etapes);
    }
    etapes.add(EtapeBorne('Utilisateur borne', EtatEtapeBorne.ok, '« ${c.login} »'));
    final mdp = await secrets.lire();
    if (mdp == null || mdp.isEmpty) {
      etapes.add(const EtapeBorne('Mot de passe', EtatEtapeBorne.echec,
          'Mot de passe de l\'utilisateur borne absent sur cet appareil : saisissez-le, puis Enregistrer.'));
      return DiagnosticBorne(etapes);
    }
    etapes.add(const EtapeBorne('Mot de passe', EtatEtapeBorne.ok, 'Enregistré dans le stockage sécurisé.'));

    final dio = client?.call(baseUrl) ?? _nouveauClient();
    // 4. Connexion
    try {
      final r = await dio.post('/user/auth', data: {'login': c.login, 'password': mdp});
      final d = r.data;
      if (r.statusCode == 200 && d is Map && d['success'] == true) {
        etapes.add(const EtapeBorne('Connexion', EtatEtapeBorne.ok, 'Connexion de l\'utilisateur borne acceptée par le serveur.'));
      } else if (r.statusCode == 404 || codePasserelle(r.statusCode)) {
        // 4.3.3 : /user/auth existe sur tout serveur Prestige : Prestige en démarrage / redéploiement (jamais « refusée »).
        etapes.add(const EtapeBorne('Connexion', EtatEtapeBorne.echec, MessagesServeur.indisponible));
        return DiagnosticBorne(etapes);
      } else {
        final msg = d is Map ? '${d['msg'] ?? ''}'.trim() : '';
        etapes.add(EtapeBorne('Connexion', EtatEtapeBorne.echec,
            'Connexion refusée pour « ${c.login} »${msg.isEmpty ? (r.statusCode == 200 ? '' : ' (HTTP ${r.statusCode})') : ' ($msg)'} : '
            'vérifiez le login et le mot de passe (compte actif sur le serveur Prestige).'));
        return DiagnosticBorne(etapes);
      }
    } on DioException catch (e) {
      etapes.add(EtapeBorne('Connexion', EtatEtapeBorne.echec, _reseau(e)));
      return DiagnosticBorne(etapes);
    }

    try {
      // 5. Recherche (comme la borne : 1re catégorie en « contient », sinon « DOLI »).
      final cat = c.categories.isNotEmpty ? c.categories.first : const BorneCategorie('Douleur', 'DOLI');
      final q = serverQuery(cat.motCle, modeFor(cat.motCle, SearchMode.contient));
      try {
        final r = await dio.get('/vente/search', queryParameters: {'query': q, 'page': 1, 'start': 0, 'limit': 20});
        final d = r.data;
        final liste = d is Map ? d['data'] : null;
        if (r.statusCode == 404 || codePasserelle(r.statusCode)) {
          etapes.add(const EtapeBorne('Recherche de produits', EtatEtapeBorne.echec, MessagesServeur.indisponible));
        } else if (r.statusCode != 200 || liste is! List) {
          etapes.add(EtapeBorne('Recherche de produits', EtatEtapeBorne.echec,
              'Réponse inattendue du serveur (HTTP ${r.statusCode}) pour la recherche « ${cat.motCle} » : '
              'droits de l\'utilisateur borne à vérifier (vente / prévente).'));
        } else if (liste.isEmpty) {
          etapes.add(EtapeBorne('Recherche de produits', EtatEtapeBorne.echec,
              'Aucun produit trouvé pour la catégorie « ${cat.libelle} » (mot-clé « ${cat.motCle} ») : vérifiez le mot-clé, '
              'ou l\'emplacement (stock) de l\'utilisateur borne sur le serveur.'));
        } else {
          final total = d is Map ? int.tryParse('${d['total'] ?? ''}') ?? liste.length : liste.length;
          etapes.add(EtapeBorne('Recherche de produits', EtatEtapeBorne.ok,
              '$total produit${total > 1 ? 's' : ''} pour la catégorie « ${cat.libelle} » (« ${cat.motCle} »).'));
        }
      } on DioException catch (e) {
        etapes.add(EtapeBorne('Recherche de produits', EtatEtapeBorne.echec, _reseau(e)));
      }
      // 6. Produits mis en avant.
      if (c.vedettes.isNotEmpty) {
        final absents = <String>[];
        for (final code in c.vedettes) {
          try {
            final r = await dio.get('/vente/search', queryParameters: {'query': code, 'page': 1, 'start': 0, 'limit': 20});
            final liste = r.data is Map ? (r.data as Map)['data'] : null;
            final trouve = liste is List && liste.any((p) => p is Map && '${p['intCIP'] ?? ''}'.trim() == code);
            if (!trouve) absents.add(code);
          } on DioException {
            absents.add(code);
          }
        }
        etapes.add(absents.isEmpty
            ? EtapeBorne('Produits mis en avant', EtatEtapeBorne.ok, '${c.vedettes.length} trouvé${c.vedettes.length > 1 ? 's' : ''}.')
            : EtapeBorne('Produits mis en avant', EtatEtapeBorne.attention, 'Introuvable${absents.length > 1 ? 's' : ''} : ${absents.join(', ')}.'));
      }
    } finally {
      try {
        await dio.post('/user/logout');
      } catch (_) {}
    }
    return DiagnosticBorne(etapes);
  }
}

/// Fenêtre du résultat du test (étapes ✓ / ! / ✗ et conclusion).
class DiagnosticBorneVue extends StatelessWidget {
  final DiagnosticBorne d;
  const DiagnosticBorneVue(this.d, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('borne-diagnostic'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in d.etapes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  switch (e.etat) {
                    EtatEtapeBorne.ok => Icons.check_circle,
                    EtatEtapeBorne.attention => Icons.info,
                    EtatEtapeBorne.echec => Icons.cancel,
                  },
                  color: switch (e.etat) {
                    EtatEtapeBorne.ok => Pal.green,
                    EtatEtapeBorne.attention => const Color(0xFFB45309),
                    EtatEtapeBorne.echec => const Color(0xFFB91C1C),
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.titre, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.ink)),
                    Text(e.detail, style: const TextStyle(fontSize: 13, color: Pal.ink)),
                  ]),
                ),
              ]),
            ),
          const Divider(),
          Text(d.conclusion,
              key: const ValueKey('borne-diagnostic-conclusion'),
              style: TextStyle(fontWeight: FontWeight.w700, color: d.ok ? Pal.green : const Color(0xFF991B1B))),
        ],
      );
}
