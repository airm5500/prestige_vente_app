// 5.3.0 — UNITAIRES : pointage sur un terminal SANS le service d'empreinte Sunmi (ex. SUNMI V3, Android 13).
//  - détection automatique par le canal natif `prestige/fingerprint` SIMULÉ : service présent (piste 4), absent sur un
//    terminal Sunmi / à lecteur (bandeau), absent sur une tablette sans lecteur (rien), canal absent (rien) ;
//  - réglage « Confirmer le pointage par empreinte » : DÉSACTIVÉ par défaut, enregistré, relu, autres réglages intacts ;
//  - confirmation Android (BiometricPrompt simulé par le canal) : reconnue, annulée, délai, trop d'essais, aucune
//    empreinte enregistrée (avant ou pendant la demande), pas de lecteur, lecteur en panne, canal absent ;
//  - textes : bandeau et réglage exactement ceux demandés par le pharmacien.
// Données FICTIVES seulement.
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/rh/confirmation_empreinte.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/empreinte_terminal_fictif.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('détection du service d\'empreinte Sunmi (canal simulé)', () {
    test('service présent (ancien terminal) → empreinte, pas de bandeau (piste 4)', () async {
      CanalEmpreinteSimule(service: true, materiel: materielAncienSunmi()).installerGlobal();
      final c = await IdentificationEmploye(nfc: FauxNfcEmpreinte(), coffre: CoffreEmpreintesMemoire()).detecter();
      expect(c.empreinte, isTrue);
      expect(c.lecteurSansIdentification, isFalse);
      expect(c.ordre.first, MoyenIdentification.empreinte);
    });

    test('service absent sur SUNMI V3 → pas d\'empreinte, bandeau', () async {
      final canal = CanalEmpreinteSimule(service: false)..installerGlobal();
      final c = await IdentificationEmploye(nfc: FauxNfcEmpreinte(), coffre: CoffreEmpreintesMemoire()).detecter();
      expect(c.empreinte, isFalse);
      expect(c.lecteurSansIdentification, isTrue);
      expect(c.ordre, isNot(contains(MoyenIdentification.empreinte)));
      expect(canal.appelsDe('isServiceInstalled'), hasLength(1));
      expect(canal.appelsDe('authenticate'), isEmpty, reason: 'aucune demande d\'empreinte à la détection');
    });

    test('service absent, appareil à lecteur (non Sunmi) → bandeau ; tablette sans lecteur → rien', () async {
      final canal = CanalEmpreinteSimule(materiel: {...materielSunmiV3(), 'manufacturer': 'Samsung'})..installerGlobal();
      final id = IdentificationEmploye(nfc: FauxNfcEmpreinte(), coffre: CoffreEmpreintesMemoire());
      expect((await id.detecter()).lecteurSansIdentification, isTrue);
      canal.materiel = materielTablette();
      expect((await id.detecter()).lecteurSansIdentification, isFalse);
    });

    test('canal absent (autre appareil, tests) → ni empreinte ni bandeau, sans exception', () async {
      final c = await IdentificationEmploye(nfc: FauxNfcEmpreinte(), coffre: CoffreEmpreintesMemoire()).detecter();
      expect(c.empreinte, isFalse);
      expect(c.lecteurSansIdentification, isFalse);
    });
  });

  group('réglage « Confirmer le pointage par empreinte »', () {
    test('DÉSACTIVÉ par défaut (préférences vides ou illisibles, constructeur)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(const ReglagesPointageTerminal().confirmationEmpreinte, isFalse);
      expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isFalse);
    });

    test('enregistré et relu ; les autres réglages ne bougent pas', () async {
      SharedPreferences.setMockInitialValues({ReglagesPointageTerminal.prefPhoto: false, ReglagesPointageTerminal.prefRetention: 15});
      final r = await ReglagesPointageTerminal.charger();
      await r.copie(confirmationEmpreinte: true).enregistrer();
      final p = await SharedPreferences.getInstance();
      expect(p.getBool(ReglagesPointageTerminal.prefConfirmationEmpreinte), isTrue);
      expect(ReglagesPointageTerminal.prefConfirmationEmpreinte, 'rh_confirmation_empreinte_v1');
      final relu = await ReglagesPointageTerminal.charger();
      expect(relu.confirmationEmpreinte, isTrue);
      expect(relu.photoBadge, isFalse);
      expect(relu.retentionJours, 15);
      expect(relu.simpleBouton, isTrue);
      await relu.copie(photoBadge: true).enregistrer();
      expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isTrue, reason: 'copie conserve le réglage');
      await relu.copie(confirmationEmpreinte: false).enregistrer();
      expect((await ReglagesPointageTerminal.charger()).confirmationEmpreinte, isFalse);
    });
  });

  group('confirmation Android (BiometricPrompt simulé par le canal)', () {
    Future<(IssueConfirmation, CanalEmpreinteSimule)> confirmer({String? reponse, Map<String, Object?>? materiel}) async {
      final canal = CanalEmpreinteSimule(materiel: materiel, reponseAuthentification: reponse)..installerGlobal();
      return (await const ConfirmationEmpreinte().confirmer(prenom: 'Alpha'), canal);
    }

    test('empreinte reconnue → confirmée (pointage autorisé, sans mention)', () async {
      final (i, canal) = await confirmer();
      expect(i, IssueConfirmation.confirmee);
      expect(i.autorise, isTrue);
      expect(i.mention, isNull);
      final a = canal.appelsDe('authenticate').single.arguments as Map;
      expect(a['title'], 'Confirmer le pointage');
      expect(a['subtitle'], 'Alpha, posez un doigt enregistré sur ce terminal');
    });

    test('annulation et délai dépassé → annulée : pointage NON enregistré, nouvel essai proposé', () async {
      for (final code in ['CANCELED', 'TIMEOUT', 'false']) {
        final (i, _) = await confirmer(reponse: code);
        expect(i, IssueConfirmation.annulee, reason: code);
        expect(i.autorise, isFalse);
        expect(i.refus, contains('réessayer'));
      }
    });

    test('trop d\'essais ratés / erreur de lecture → échec : pointage NON enregistré', () async {
      for (final code in ['LOCKOUT', 'AUTH_ERROR', 'INCONNU']) {
        final (i, _) = await confirmer(reponse: code);
        expect(i, IssueConfirmation.echec, reason: code);
        expect(i.autorise, isFalse);
        expect(i.refus, 'Empreinte non confirmée. Présentez de nouveau votre badge ou votre code pour réessayer.');
      }
    });

    test('aucune empreinte enregistrée (vu avant la demande) → autorisé avec mention, AUCUNE fenêtre Android', () async {
      final (i, canal) = await confirmer(materiel: materielSunmiV3(biometricStatus: 11));
      expect(i, IssueConfirmation.sansEmpreinte);
      expect(i.autorise, isTrue);
      expect(i.mention, contains('aucune empreinte enregistrée'));
      expect(canal.appelsDe('authenticate'), isEmpty);
    });

    test('aucune empreinte enregistrée (signalé par Android) → autorisé avec mention', () async {
      final (i, _) = await confirmer(reponse: 'NONE_ENROLLED', materiel: materielSunmiV3(biometricStatus: null));
      expect(i, IssueConfirmation.sansEmpreinte);
      expect(i.autorise, isTrue);
    });

    test('pas de lecteur (déclaré, statut 12, Android < 9, matériel absent) → autorisé avec mention', () async {
      for (final (m, r) in [
        (materielSunmiV3(lecteur: false), null),
        (materielSunmiV3(biometricStatus: 12), null),
        (materielSunmiV3(), 'NOT_SUPPORTED'),
        (materielSunmiV3(), 'NO_HARDWARE'),
      ]) {
        final (i, _) = await confirmer(materiel: m, reponse: r);
        expect(i, IssueConfirmation.sansLecteur, reason: '$m $r');
        expect(i.autorise, isTrue);
        expect(i.mention, contains('pas de lecteur'));
      }
    });

    test('lecteur en panne (statut 1, HW_ERROR) → autorisé avec mention', () async {
      for (final (m, r) in [(materielSunmiV3(biometricStatus: 1), null), (materielSunmiV3(), 'HW_ERROR')]) {
        final (i, _) = await confirmer(materiel: m, reponse: r);
        expect(i, IssueConfirmation.erreurLecteur, reason: '$r');
        expect(i.autorise, isTrue);
        expect(i.mention, contains('indisponible'));
      }
    });

    test('canal absent (pas de pont natif) → pas de lecteur, autorisé', () async {
      expect(await const ConfirmationEmpreinte().confirmer(), IssueConfirmation.sansLecteur);
    });

    test('journal : aucune donnée personnelle (ni prénom, ni badge, ni code)', () {
      for (final i in IssueConfirmation.values) {
        expect(i.journal, isNot(contains('Alpha')));
        expect(i.journal, startsWith('Confirmation par empreinte'));
      }
    });
  });

  group('textes demandés par le pharmacien', () {
    test('bandeau', () {
      expect(texteSansEmpreinte,
          'Ce terminal ne permet pas la reconnaissance par empreinte. Pointez avec votre badge ou votre code personnel.');
    });

    test('réglage : titre et avertissement « n\'identifie pas la personne »', () {
      expect(titreReglageConfirmationEmpreinte, 'Confirmer le pointage par empreinte');
      expect(texteReglageConfirmationEmpreinte,
          contains('Android accepte toute empreinte enregistrée sur ce terminal : cela décourage la fraude mais n\'identifie pas la personne.'));
    });
  });
}
