// lib/services/identifiants_securises.dart
// Mot de passe de connexion mémorisé (« Rester connecté ») : gardé dans le stockage sécurisé d'Android
// (flutter_secure_storage, chiffré par le Keystore, exclu des sauvegardes — res/xml/regles_*.xml),
// et non plus en clair dans SharedPreferences (ancienne clé `saved_password`).
//
// Point d'accès unique : [IdentifiantsSecurises.instance] (lire / écrire / effacer).
// MIGRATION transparente : si l'ancienne clé en clair existe, elle est copiée dans le stockage sûr,
// la copie est relue et vérifiée, puis la clé en clair est SUPPRIMÉE. Si le stockage sûr échoue
// (Keystore indisponible, exception…), on garde l'ancien comportement (clé en clair) pour ne pas
// perdre la connexion automatique, et on réessaie au lancement suivant. Chaque échec est noté dans le
// journal du terminal — jamais le mot de passe.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stockage sûr d'une valeur (remplaçable dans les tests pour simuler une panne du Keystore).
abstract class CoffreIdentifiants {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
  Future<void> effacer(String cle);
}

/// Stockage sécurisé Android (Keystore) via flutter_secure_storage.
class CoffreIdentifiantsSecurise implements CoffreIdentifiants {
  final FlutterSecureStorage _s;
  const CoffreIdentifiantsSecurise([this._s = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true))]);

  @override
  Future<String?> lire(String cle) => _s.read(key: cle);
  @override
  Future<void> ecrire(String cle, String valeur) => _s.write(key: cle, value: valeur);
  @override
  Future<void> effacer(String cle) => _s.delete(key: cle);
}

class IdentifiantsSecurises {
  /// Ancienne clé, en clair dans SharedPreferences (lue seulement pour la migration / le repli).
  static const cleClaire = 'saved_password';

  /// Clé dans le stockage sécurisé.
  static const cleSure = 'connexion_mot_de_passe_v1';

  /// Délai au-delà duquel une opération du stockage sûr est considérée en échec.
  static const delai = Duration(seconds: 5);

  final CoffreIdentifiants coffre;
  final JournalTerminal Function() _journal;

  IdentifiantsSecurises({CoffreIdentifiants? coffre, JournalTerminal Function()? journal})
      : coffre = coffre ?? const CoffreIdentifiantsSecurise(),
        _journal = journal ?? (() => JournalTerminal.instance);

  /// Instance de l'appli (remplaçable dans les tests).
  static IdentifiantsSecurises instance = IdentifiantsSecurises();

  /// Migration déjà réussie (ou rien à migrer) pendant ce lancement.
  bool _migre = false;
  Future<bool>? _migrationEnCours;

  /// Migre l'ancienne clé en clair vers le stockage sûr. Renvoie `true` si plus aucun mot de passe
  /// n'est en clair. N'échoue jamais (en cas d'échec, l'ancienne clé est gardée et l'échec journalisé).
  Future<bool> migrer() {
    if (_migre) return Future.value(true);
    return _migrationEnCours ??= _migrer().whenComplete(() => _migrationEnCours = null);
  }

  Future<bool> _migrer() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    final clair = prefs.getString(cleClaire);
    if (clair == null) {
      _migre = true;
      return true;
    }
    try {
      await coffre.ecrire(cleSure, clair).timeout(delai);
      final relu = await coffre.lire(cleSure).timeout(delai);
      if (relu != clair) throw const _RelectureDifferente();
    } catch (e) {
      _noterEchec('Migration du mot de passe mémorisé vers le stockage sécurisé', e, clair);
      return false;
    }
    await prefs.remove(cleClaire);
    _migre = true;
    _journal().noter(
      type: TypeJournal.connexion,
      action: 'Mot de passe mémorisé déplacé dans le stockage sécurisé',
      resultat: ResultatJournal.info,
    );
    return true;
  }

  /// Mot de passe mémorisé, ou `null` s'il n'y en a pas.
  Future<String?> lire() async {
    await migrer();
    // Clé en clair encore présente = stockage sûr en échec : c'est elle la plus récente.
    try {
      final clair = (await SharedPreferences.getInstance()).getString(cleClaire);
      if (clair != null) return clair;
    } catch (_) {}
    try {
      return await coffre.lire(cleSure).timeout(delai);
    } catch (e) {
      _noterEchec('Lecture du mot de passe mémorisé', e, null);
      return null;
    }
  }

  /// Mémorise le mot de passe (stockage sûr ; repli en clair si le stockage sûr échoue).
  Future<void> ecrire(String motDePasse) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await coffre.ecrire(cleSure, motDePasse).timeout(delai);
      final relu = await coffre.lire(cleSure).timeout(delai);
      if (relu != motDePasse) throw const _RelectureDifferente();
    } catch (e) {
      _noterEchec('Enregistrement du mot de passe mémorisé', e, motDePasse);
      // Ancien comportement gardé pour cette fois (connexion automatique conservée) ;
      // la migration le déplacera au lancement suivant.
      await prefs.setString(cleClaire, motDePasse);
      return;
    }
    await prefs.remove(cleClaire);
  }

  /// Oublie le mot de passe partout (stockage sûr ET ancienne clé en clair).
  Future<void> effacer() async {
    try {
      await (await SharedPreferences.getInstance()).remove(cleClaire);
    } catch (_) {}
    try {
      await coffre.effacer(cleSure).timeout(delai);
    } catch (e) {
      _noterEchec('Effacement du mot de passe mémorisé', e, null);
    }
  }

  void _noterEchec(String action, Object e, String? secret) {
    var motif = e is PlatformException
        ? 'stockage sécurisé indisponible (${e.code})'
        : e is _RelectureDifferente
            ? 'relecture du stockage sécurisé différente'
            : e is TimeoutException
                ? 'stockage sécurisé : délai dépassé'
                : 'stockage sécurisé indisponible (${e.runtimeType})';
    if (secret != null && secret.isNotEmpty) motif = motif.replaceAll(secret, '***');
    debugPrint('Identifiants : $action — $motif ; ancien comportement conservé, nouvel essai au prochain lancement');
    try {
      _journal().noter(
        type: TypeJournal.connexion,
        action: action,
        resultat: ResultatJournal.refus,
        motif: '$motif ; ancien comportement conservé, nouvel essai au prochain lancement',
      );
    } catch (_) {}
  }
}

class _RelectureDifferente implements Exception {
  const _RelectureDifferente();
}
