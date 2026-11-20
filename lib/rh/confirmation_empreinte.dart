// lib/rh/confirmation_empreinte.dart
// 5.3.0 — Pointage sur un terminal SANS le service d'empreinte Sunmi (com.sunmi.fingerprintservice), par exemple le
// SUNMI V3 (Android 13) : décision du pharmacien (pistes 1, 2 et 4).
//  1. Badge et code : au lieu d'un diagnostic technique, un bandeau clair (« Ce terminal ne permet pas la
//     reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel. ») avec accès direct au
//     badge (QR / code-barres par la caméra, NFC, lecteur) et au code personnel (n° de badge ou matricule au clavier) ;
//     un lien discret « Détails techniques » ouvre le diagnostic du lecteur.
//  2. Confirmation par le doigt (réglage administrateur, DÉSACTIVÉ par défaut) : après l'identification par badge ou
//     code, Android demande une empreinte (BiometricPrompt, pont natif existant `prestige/fingerprint`, méthode
//     `authenticate` : aucune bibliothèque ajoutée, activité inchangée). Android accepte TOUTE empreinte enregistrée
//     sur le terminal : cela décourage la fraude mais n'identifie pas la personne.
//       - empreinte reconnue → pointage enregistré ;
//       - aucune empreinte enregistrée, pas de lecteur, lecteur en panne → pointage enregistré quand même, avec une
//         mention à l'écran ;
//       - annulation, délai dépassé, trop d'essais ratés → pointage NON enregistré, message clair, nouvel essai
//         possible tout de suite.
//  4. Service Sunmi présent (anciens terminaux) : fonctionnement inchangé (identification 1:N par le doigt,
//     enrôlement, synchronisation des modèles selon le réglage du serveur et le droit) ; la confirmation n'y est
//     jamais demandée. Détection automatique à l'ouverture de l'écran.
// Rien de personnel ici : ni nom, ni code, ni modèle d'empreinte dans un journal ; Android ne rend aucune donnée
// d'empreinte (seulement « reconnue / non »).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/services/fingerprint_service.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

/// Texte du bandeau (terminal sans reconnaissance par empreinte).
const String texteSansEmpreinte =
    'Ce terminal ne permet pas la reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel.';

/// Variante pour l'écran d'enrôlement (gestionnaire).
const String texteSansEmpreinteGestion =
    'Ce terminal ne permet pas la reconnaissance par empreinte : aucune empreinte ne peut y être enregistrée. Les '
    'employés pointent avec leur badge ou leur code personnel.';

/// Réglage administrateur (titre et explication).
const String titreReglageConfirmationEmpreinte = 'Confirmer le pointage par empreinte';
const String texteReglageConfirmationEmpreinte =
    'Après le badge ou le code personnel, l\'employé pose un doigt sur le lecteur du terminal. Android accepte toute '
    'empreinte enregistrée sur ce terminal : cela décourage la fraude mais n\'identifie pas la personne. Sans empreinte '
    'enregistrée ou sans lecteur, le pointage par badge ou code se fait quand même (avec une mention). Terminaux qui '
    'reconnaissent l\'empreinte (service Sunmi) : rien ne change.';

/// Rappel affiché sous la zone du badge quand la confirmation est active.
const String texteConfirmationActive = 'Après le badge ou le code, posez un doigt enregistré sur le lecteur pour confirmer.';

/// Issue de la demande d'empreinte Android.
enum IssueConfirmation {
  /// Une empreinte enregistrée sur le terminal a été reconnue.
  confirmee,

  /// L'employé a annulé (ou n'a pas posé le doigt à temps).
  annulee,

  /// Empreinte refusée (trop d'essais ratés, erreur de lecture).
  echec,

  /// Aucune empreinte enregistrée dans les Paramètres Android du terminal.
  sansEmpreinte,

  /// Pas de lecteur d'empreinte (ou Android trop ancien).
  sansLecteur,

  /// Lecteur présent mais indisponible / en panne.
  erreurLecteur,
}

extension IssueConfirmationInfo on IssueConfirmation {
  /// Le pointage peut être enregistré.
  bool get autorise => this != IssueConfirmation.annulee && this != IssueConfirmation.echec;

  /// Mention affichée avec le pointage enregistré SANS confirmation (null : rien à signaler).
  String? get mention => switch (this) {
        IssueConfirmation.sansEmpreinte => 'Pointage sans confirmation par empreinte : aucune empreinte enregistrée sur ce terminal.',
        IssueConfirmation.sansLecteur => 'Pointage sans confirmation par empreinte : pas de lecteur d\'empreinte sur ce terminal.',
        IssueConfirmation.erreurLecteur => 'Pointage sans confirmation par empreinte : lecteur d\'empreinte indisponible.',
        _ => null,
      };

  /// Message quand le pointage n'est PAS enregistré.
  String get refus => switch (this) {
        IssueConfirmation.annulee => 'Confirmation par empreinte annulée. Présentez de nouveau votre badge ou votre code pour réessayer.',
        _ => 'Empreinte non confirmée. Présentez de nouveau votre badge ou votre code pour réessayer.',
      };

  /// Journal du terminal (aucune donnée personnelle).
  String get journal => switch (this) {
        IssueConfirmation.confirmee => 'Confirmation par empreinte : reconnue',
        IssueConfirmation.annulee => 'Confirmation par empreinte : annulée, pointage non enregistré',
        IssueConfirmation.echec => 'Confirmation par empreinte : refusée, pointage non enregistré',
        IssueConfirmation.sansEmpreinte => 'Confirmation par empreinte impossible (aucune empreinte enregistrée), pointage accepté',
        IssueConfirmation.sansLecteur => 'Confirmation par empreinte impossible (pas de lecteur), pointage accepté',
        IssueConfirmation.erreurLecteur => 'Confirmation par empreinte impossible (lecteur indisponible), pointage accepté',
      };
}

/// Demande d'empreinte Android (BiometricPrompt) — remplaçable pour les tests ; par défaut le pont natif.
class ConfirmationEmpreinte {
  /// État du lecteur Android (featureFingerprint, biometricStatus) : FingerprintService.hardwareInfo.
  final Future<Map<String, Object?>> Function() materiel;

  /// BiometricPrompt : true = reconnue, false = annulée ; FingerprintException sinon.
  final Future<bool> Function({String title, String subtitle}) demander;

  const ConfirmationEmpreinte({
    this.materiel = FingerprintService.hardwareInfo,
    this.demander = FingerprintService.authenticate,
  });

  /// Demande l'empreinte ; [prenom] n'est affiché que dans la fenêtre d'Android (jamais gardé).
  Future<IssueConfirmation> confirmer({String prenom = ''}) async {
    Map<String, Object?> hw;
    try {
      hw = await materiel();
    } on FingerprintException catch (e) {
      return e.code == 'NO_PLUGIN' ? IssueConfirmation.sansLecteur : IssueConfirmation.erreurLecteur;
    } catch (_) {
      return IssueConfirmation.erreurLecteur;
    }
    if (hw['featureFingerprint'] != true) return IssueConfirmation.sansLecteur;
    // BiometricManager.canAuthenticate() (Android 10+) : 0 prêt, 11 aucune empreinte, 12 pas de lecteur,
    // 1 lecteur indisponible ; absent (Android 9) : on demande quand même.
    switch (hw['biometricStatus']) {
      case 11:
        return IssueConfirmation.sansEmpreinte;
      case 12:
        return IssueConfirmation.sansLecteur;
      case 1:
        return IssueConfirmation.erreurLecteur;
    }
    try {
      final ok = await demander(
        title: 'Confirmer le pointage',
        subtitle: prenom.isEmpty ? 'Posez un doigt enregistré sur ce terminal' : '$prenom, posez un doigt enregistré sur ce terminal',
      );
      return ok ? IssueConfirmation.confirmee : IssueConfirmation.annulee;
    } on FingerprintException catch (e) {
      return switch (e.code) {
        'CANCELED' || 'TIMEOUT' => IssueConfirmation.annulee,
        'NONE_ENROLLED' => IssueConfirmation.sansEmpreinte,
        'NO_PLUGIN' || 'NOT_SUPPORTED' || 'NO_HARDWARE' => IssueConfirmation.sansLecteur,
        'HW_ERROR' => IssueConfirmation.erreurLecteur,
        _ => IssueConfirmation.echec, // LOCKOUT (trop d'essais), AUTH_ERROR
      };
    } catch (_) {
      return IssueConfirmation.echec;
    }
  }
}

/// Bandeau du terminal sans reconnaissance par empreinte : badge, code personnel, détails techniques.
class BandeauSansEmpreinte extends StatelessWidget {
  final VoidCallback? onBadge;
  final VoidCallback? onCode;

  /// Lien discret vers le diagnostic du lecteur (null : masqué, par exemple en mode borne).
  final VoidCallback? onDetails;

  /// Texte (pointage ou gestion).
  final String texte;
  const BandeauSansEmpreinte({super.key, this.onBadge, this.onCode, this.onDetails, this.texte = texteSansEmpreinte});

  @override
  Widget build(BuildContext context) {
    // Téléphone / terminal (< 600 dp) : boutons côte à côte (libellé sur deux lignes au besoin) pour laisser la zone
    // du badge à l'écran ; texte un peu plus petit sous 400 dp.
    final largeur = MediaQuery.sizeOf(context).width;
    final etroit = largeur < 600;
    Widget bouton(Widget b) => etroit ? Expanded(child: b) : b;
    final libelle = TextStyle(fontSize: largeur <= 400 ? 13.5 : 14.5, fontWeight: FontWeight.w600);
    final boutons = [
      if (onBadge != null)
        bouton(ElevatedButton.icon(
          key: const Key('rh_sans_empreinte_badge'),
          style: navyButton.copyWith(
            minimumSize: WidgetStatePropertyAll(Size(etroit ? 0 : 170, 48)),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
          ),
          onPressed: onBadge,
          icon: const Icon(Icons.qr_code_scanner, size: 20),
          label: Text('Scanner mon badge', textAlign: TextAlign.center, style: libelle),
        )),
      if (onCode != null)
        bouton(OutlinedButton.icon(
          key: const Key('rh_sans_empreinte_code'),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(etroit ? 0 : 170, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            backgroundColor: Colors.white,
            foregroundColor: Pal.navy,
            side: const BorderSide(color: Pal.navy),
          ),
          onPressed: onCode,
          icon: const Icon(Icons.dialpad, size: 20),
          label: Text('Saisir mon code personnel', textAlign: TextAlign.center, style: libelle),
        )),
    ];
    return Container(
      key: const Key('rh_sans_empreinte'),
      padding: EdgeInsets.fromLTRB(etroit ? 10 : 14, 10, etroit ? 10 : 14, onDetails == null ? 10 : 0),
      decoration: BoxDecoration(
        color: const Color(0xFFE3ECF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB8CBE4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, color: Pal.navy)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texte,
                key: const Key('rh_sans_empreinte_texte'),
                style: TextStyle(fontSize: largeur <= 400 ? 14 : 15, fontWeight: FontWeight.w600, color: Pal.ink, height: 1.3)),
          ),
        ]),
        if (boutons.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (etroit)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < boutons.length; i++) ...[if (i > 0) const SizedBox(width: 8), boutons[i]],
              ]),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: boutons),
        ],
        if (onDetails != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('rh_sans_empreinte_details'),
              style: TextButton.styleFrom(
                foregroundColor: Pal.muted,
                textStyle: const TextStyle(fontSize: 12.5),
                minimumSize: const Size(48, 48),
              ),
              onPressed: onDetails,
              child: const Text('Détails techniques'),
            ),
          ),
      ]),
    );
  }
}

/// Panneau affiché pendant la demande d'empreinte d'Android (la fenêtre d'Android s'affiche par-dessus).
class PanneauConfirmationEmpreinte extends StatelessWidget {
  final String prenom;
  const PanneauConfirmationEmpreinte({super.key, required this.prenom});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('rh_confirmation_empreinte'),
        color: Colors.white,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.fingerprint, size: 96, color: Pal.navy),
              const SizedBox(height: 12),
              Text('Bonjour $prenom',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Pal.ink)),
              const SizedBox(height: 8),
              const Text('Confirmez votre pointage : posez un doigt enregistré sur le lecteur.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Pal.navy)),
              const SizedBox(height: 16),
              const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
            ]),
          ),
        ),
      );
}
