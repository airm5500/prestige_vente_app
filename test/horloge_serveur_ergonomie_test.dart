// 5.5.0 — Ergonomie du refus « heure du serveur fausse » (transmission du 24/11/2026) : textes en français, jamais
// présentés comme une panne réseau / une erreur inconnue, aucun contournement proposé ; bandeau de connexion lisible
// sur un petit écran (360 px, texte agrandi) en clair et en sombre ; libellé d'attente du terminal distinct du hors
// ligne. Données fictives uniquement.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/connexion/connexion_commun.dart';
import 'package:prestige_vente_app/rh/pointage_rh.dart';
import 'package:prestige_vente_app/serveur/horloge_serveur.dart';

const _msg = 'Opération refusée : l\'heure du serveur est fausse. L\'administrateur doit la corriger sur le serveur.';

void main() {
  final bandeau = const HorlogePublique(EtatHorloge.bloque, '24/11/2026 20:52').texteBandeau!;
  final textes = <String, String>{
    'défaut': messageHorlogeParDefaut,
    'bandeau': bandeau,
    'attente terminal': etatAttenteHorloge,
    'pointage gardé': messageHorlogeFile(_msg, '08:02'),
    'bilan': const BilanEnvoiRh(interrompu: true, horloge: _msg).message,
    'titre': titreHorlogeBloquee,
  };

  test('jamais « réseau », « injoignable », « inconnue » ; aucun contournement proposé', () {
    for (final e in textes.entries) {
      final t = e.value.toLowerCase();
      for (final interdit in ['réseau', 'injoignable', 'inconnu', 'wi-fi', 'réessayez', 'changez l\'heure', 'modifiez l\'heure', 'paramètres']) {
        expect(t, isNot(contains(interdit)), reason: '${e.key} : « $interdit »');
      }
    }
  });

  test('message du serveur repris tel quel, en tête ; attente distincte du hors ligne', () {
    expect(messageHorlogeFile(_msg, '08:02'), startsWith(_msg));
    expect(const BilanEnvoiRh(interrompu: true, horloge: _msg).message, contains(_msg));
    expect(etatAttenteHorloge, isNot(etatEnAttenteEnvoi));
    expect(etatAttenteHorloge, contains('heure du serveur'));
  });

  for (final sombre in [false, true]) {
    testWidgets('bandeau lisible à 360 px, texte agrandi (${sombre ? 'sombre' : 'clair'})', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: sombre ? Brightness.dark : Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: BandeauHorlogeServeur(bandeau))),
        ),
      ));
      expect(t.takeException(), isNull, reason: 'aucun débordement');
      expect(find.text(titreHorlogeBloquee), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget, reason: 'icône en plus de la couleur');
      final taille = t.getSize(find.byKey(const Key('bandeau_horloge_serveur')));
      expect(taille.width, lessThanOrEqualTo(328));
    });
  }
}
