// lib/connexion/pin_personnel.dart
// Code PIN personnel (connexion rapide « Qui êtes-vous ? », option C).
//
// Sécurité :
//  - le PIN (4 chiffres) n'est JAMAIS gardé en clair : empreinte PBKDF2-HMAC-SHA256 salée (EmpreintePin,
//    120 000 itérations, sel aléatoire) dans le stockage sécurisé Android (Keystore) ;
//  - règles anti-PIN faibles existantes (ReglesPin : pas de 1234, de chiffres identiques, de suite ni de motif) ;
//  - le PIN ne remplace pas la connexion au serveur : il débloque le mot de passe de l'utilisateur, gardé
//    chiffré PAR UTILISATEUR dans le même stockage sécurisé, puis la connexion normale est faite au serveur ;
//    sans mot de passe gardé, le mot de passe est demandé ;
//  - 3 PIN faux → PIN verrouillé : le mot de passe complet (vérifié par le serveur) est exigé ; le compteur
//    repart à zéro après une connexion par mot de passe réussie ;
//  - le serveur refuse le mot de passe gardé (mot de passe changé) → PIN et mot de passe gardé effacés ;
//  - réinitialisation par l'administrateur (Paramètres › Sécurité), ou en retirant l'utilisateur de la liste.
// Les logins ne servent de clé que sous forme encodée ; aucun secret dans le journal ni les préférences.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:prestige_vente_app/connexion/connexion_reglages.dart';
import 'package:prestige_vente_app/services/identifiants_securises.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ResultatPin {
  /// Code correct : le mot de passe gardé est rendu.
  accepte,

  /// Code incorrect (essais restants : [PinPersonnel.essaisRestants]).
  refuse,

  /// 3 erreurs : mot de passe complet exigé.
  verrouille,

  /// Pas de PIN ou pas de mot de passe gardé pour cet utilisateur : mot de passe exigé.
  absent,

  /// Stockage sécurisé illisible.
  indisponible,
}

class PinPersonnel {
  static const longueur = 4;
  static const erreursMax = 3;
  static const delai = Duration(seconds: 5);

  static const _prefixePin = 'pin_perso_v1_';
  static const _prefixeMdp = 'mdp_perso_v1_';
  static const _prefixeEchecs = 'pin_perso_echecs_v1_';

  /// Logins (normalisés) qui ont un PIN sur cet appareil (pour la réinitialisation par l'administrateur).
  static const cleListe = 'pin_perso_logins_v1';

  final CoffreIdentifiants coffre;
  final int iterations;

  PinPersonnel({CoffreIdentifiants? coffre, int? iterations})
      : coffre = coffre ?? const CoffreIdentifiantsSecurise(),
        iterations = iterations ?? EmpreintePin.iterationsParDefaut;

  /// Instance de l'appli (remplaçable dans les tests).
  static PinPersonnel instance = PinPersonnel();

  static String _id(String login) => base64Url.encode(utf8.encode(DerniersUtilisateurs.normaliser(login))).replaceAll('=', '');

  /// Motif de refus d'un nouveau PIN personnel, ou `null`.
  static String? refus(String pin) {
    if (!RegExp('^\\d{$longueur}\$').hasMatch(pin)) return 'Le code doit compter exactement $longueur chiffres.';
    return ReglesPin.refus(pin);
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Set<String>> logins() async {
    try {
      return ((await _prefs).getStringList(cleListe) ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  /// L'utilisateur a un PIN ET un mot de passe gardé sur cet appareil.
  Future<bool> actif(String login) async {
    if (!(await logins()).contains(DerniersUtilisateurs.normaliser(login))) return false;
    try {
      final e = await coffre.lire('$_prefixePin${_id(login)}').timeout(delai);
      final m = await coffre.lire('$_prefixeMdp${_id(login)}').timeout(delai);
      return EmpreintePin.estEmpreinte(e) && m != null && m.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int> erreurs(String login) async {
    try {
      return (await _prefs).getInt('$_prefixeEchecs${_id(login)}') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> essaisRestants(String login) async => (erreursMax - await erreurs(login)).clamp(0, erreursMax);

  Future<bool> verrouille(String login) async => await erreurs(login) >= erreursMax;

  /// Crée (ou remplace) le PIN de [login] et garde son mot de passe [motDePasse] (déjà vérifié par le
  /// serveur). Renvoie le motif de refus, ou `null` si enregistré.
  Future<String?> definir(String login, String pin, String motDePasse) async {
    final motif = refus(pin);
    if (motif != null) return motif;
    if (motDePasse.isEmpty) return 'Mot de passe manquant.';
    final id = _id(login);
    try {
      final empreinte = await _empreinte(pin);
      await coffre.ecrire('$_prefixePin$id', empreinte).timeout(delai);
      await coffre.ecrire('$_prefixeMdp$id', motDePasse).timeout(delai);
      final relu = await coffre.lire('$_prefixePin$id').timeout(delai);
      final mdp = await coffre.lire('$_prefixeMdp$id').timeout(delai);
      if (relu != empreinte || mdp != motDePasse) throw StateError('relecture différente');
    } catch (e) {
      debugPrint('PIN personnel : enregistrement impossible (${e.runtimeType})');
      await effacer(login);
      return 'Stockage sécurisé indisponible : code non enregistré.';
    }
    final prefs = await _prefs;
    await prefs.setStringList(cleListe, {...await logins(), DerniersUtilisateurs.normaliser(login)}.toList());
    await prefs.remove('$_prefixeEchecs$id');
    return null;
  }

  Future<String> _empreinte(String pin) async => EmpreintePin.creer(pin, iterations: iterations);

  /// Vérifie le PIN : rend le mot de passe gardé si le code est bon.
  Future<(ResultatPin, String?)> verifier(String login, String saisie) async {
    if (await verrouille(login)) return (ResultatPin.verrouille, null);
    if (!(await logins()).contains(DerniersUtilisateurs.normaliser(login))) return (ResultatPin.absent, null);
    final id = _id(login);
    String? empreinte, mdp;
    try {
      empreinte = await coffre.lire('$_prefixePin$id').timeout(delai);
      mdp = await coffre.lire('$_prefixeMdp$id').timeout(delai);
    } catch (_) {
      return (ResultatPin.indisponible, null);
    }
    if (empreinte == null || mdp == null || mdp.isEmpty) return (ResultatPin.absent, null);
    final ok = RegExp('^\\d{$longueur}\$').hasMatch(saisie) && EmpreintePin.verifier(saisie, empreinte);
    final prefs = await _prefs;
    if (!ok) {
      final n = (prefs.getInt('$_prefixeEchecs$id') ?? 0) + 1;
      await prefs.setInt('$_prefixeEchecs$id', n);
      return (n >= erreursMax ? ResultatPin.verrouille : ResultatPin.refuse, null);
    }
    await prefs.remove('$_prefixeEchecs$id');
    return (ResultatPin.accepte, mdp);
  }

  /// Connexion par mot de passe réussie : compteur remis à zéro et mot de passe gardé mis à jour
  /// (seulement si l'utilisateur a un PIN).
  Future<void> apresConnexionMotDePasse(String login, String motDePasse) async {
    try {
      await (await _prefs).remove('$_prefixeEchecs${_id(login)}');
    } catch (_) {}
    if (!(await logins()).contains(DerniersUtilisateurs.normaliser(login)) || motDePasse.isEmpty) return;
    try {
      await coffre.ecrire('$_prefixeMdp${_id(login)}', motDePasse).timeout(delai);
    } catch (_) {}
  }

  /// Efface le PIN, le mot de passe gardé et le compteur de [login].
  Future<void> effacer(String login) async {
    final id = _id(login);
    for (final k in ['$_prefixePin$id', '$_prefixeMdp$id']) {
      try {
        await coffre.effacer(k).timeout(delai);
      } catch (_) {}
    }
    try {
      final prefs = await _prefs;
      await prefs.remove('$_prefixeEchecs$id');
      final l = await logins()
        ..remove(DerniersUtilisateurs.normaliser(login));
      await prefs.setStringList(cleListe, l.toList());
    } catch (_) {}
  }

  /// Réinitialisation par l'administrateur : tous les PIN de l'appareil.
  Future<int> effacerTout() async {
    final l = await logins();
    for (final login in l) {
      await effacer(login);
    }
    return l.length;
  }
}
