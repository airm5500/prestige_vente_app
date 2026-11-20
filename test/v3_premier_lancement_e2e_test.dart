// E2E — Prestige Mobile V3 (5.0.0) : PREMIER LANCEMENT d'une nouvelle installation, application entière (MyApp) contre
// le faux serveur Prestige en mémoire, données FICTIVES.
// Android sépare les données de chaque application : la V3 (com.dici.prestigemobile.v3) ne voit RIEN de l'ancienne
// Prestige Mobile (réglages, connexion, nom de l'appareil, imprimante, ventes hors ligne, code administrateur). Le
// parcours d'une installation neuve doit donc marcher à partir de rien, exactement comme pour l'ancienne :
//   nom de l'appareil (étape obligatoire) → adresse par défaut (192.168.1.50) injoignable → « Configuration » sous le
//   code administrateur (code par défaut 1234 → changement obligatoire) → serveur saisi, testé, enregistré → licence
//   → connexion → accueil → vente terminée, envoyée avec le nom saisi.
// Bandeau « Ancienne application installée » (détection seulement, rien n'est lu) : affiché sur la connexion si
// l'ancienne application est installée, jusqu'à « Compris », puis plus jamais ; jamais sans elle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/accueil/accueil_screen.dart' show AccueilScreen;
import 'package:prestige_vente_app/connexion/connexion_screen.dart';
import 'package:prestige_vente_app/connexion/lancement_screen.dart';
import 'package:prestige_vente_app/identite_appli.dart';
import 'package:prestige_vente_app/parametres/parametres_screen.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';
import 'outils/parcours_vente.dart';

/// Adresse du serveur de l'officine (le faux serveur en mémoire répond sur cet hôte, pas sur l'adresse par défaut).
const _ip = '192.168.1.20';

Future<void> _toucher(WidgetTester t, AppE2E app, Finder f, {Finder? zone}) async {
  await app.defilerJusqua(t, f, zone: zone);
  await t.tap(f);
  await t.pump();
}

void main() {
  tearDown(AncienneAppli.reinitialiser);

  testWidgets('nouvelle installation (aucune donnée) : nom de l\'appareil, configuration sous code, serveur → connexion → vente',
      (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final codeAvant = CodeAdmin.instance;
    CodeAdmin.instance = CodeAdmin(iterations: 1000); // stockage sécurisé vide : code par défaut 1234
    addTearDown(() => CodeAdmin.instance = codeAvant);
    final app = AppE2E(serveur: FauxServeurPrestige(hoteEnMemoire: _ip));
    app.serveur.droitsComptes = {
      DonneesFictives.login: ['P_SM_VENTE', 'P_SM_CLOTURER_CAISSE'],
    };
    final c = CatalogueFictif(app.serveur, nombre: 10);
    await app.preparer(vierge: true, nomAppareil: null);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: 'appareil vierge : rien de l\'ancienne application');
    await app.lancer(t);
    expect(find.text(nomAppli), findsWidgets, reason: 'nom de la V3 sur le lancement');

    // 1. Nom de cet appareil : étape obligatoire d'une nouvelle installation.
    final etape = find.byKey(const Key('nom_appareil_etape'));
    expect(await app.attendreQue(t, etape), isTrue);
    await t.enterText(find.byKey(const Key('nom_appareil_champ')), 'Caisse V3');
    await _toucher(t, app, find.byKey(const Key('nom_appareil_enregistrer')),
        zone: find.descendant(of: etape, matching: find.byType(Scrollable)).first);
    expect(NomAppareil.instance.nomEnregistre, isTrue);

    // 2. Adresse par défaut injoignable : explication, « Configuration » sous le code administrateur.
    expect(await app.attendreQue(t, find.byKey(const Key('lancement_injoignable'))), isTrue);
    expect(app.serveur.recues, isEmpty, reason: 'aucune requête n\'a atteint le serveur de l\'officine');
    await t.tap(find.byKey(const Key('lancement_configuration')));
    await app.attendre(t, const Duration(seconds: 1));
    await t.enterText(find.byKey(const Key('pin_admin_saisie')), CodeAdmin.codeParDefaut);
    await t.tap(find.text('Valider'));
    await app.attendre(t, const Duration(seconds: 1));
    expect(find.text('Changement du code obligatoire'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pin_admin_nouveau')), '4827');
    await t.enterText(find.byKey(const Key('pin_admin_confirmation')), '4827');
    await t.tap(find.text('Enregistrer'));

    // 3. Réglages : serveur de l'officine saisi, testé et enregistré.
    expect(await app.attendreQue(t, find.byType(ParametresScreen)), isTrue);
    await _toucher(t, app, find.byKey(const Key('rubrique_connexion')),
        zone: find.descendant(of: find.byType(ParametresScreen), matching: find.byType(Scrollable)).first);
    await app.attendre(t, const Duration(seconds: 1));
    if (find.byKey(const Key('pin_admin_saisie')).evaluate().isNotEmpty) {
      // Rubrique à cadenas : le nouveau code administrateur.
      await t.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
      await t.tap(find.text('Valider'));
    }
    expect(await app.attendreQue(t, find.byKey(const Key('ip_locale'))), isTrue);
    await t.enterText(find.byKey(const Key('ip_locale')), _ip);
    await t.enterText(find.byKey(const Key('port')), FauxServeurPrestige.portMemoire);
    await t.enterText(find.byKey(const Key('nom_appli')), 'prestige');
    await app.attendre(t, const Duration(milliseconds: 300));
    await _toucher(t, app, find.byKey(const Key('connexion_enregistrer')));

    // 4. Redémarrage : licence vérifiée, connexion, accueil.
    expect(await app.seConnecter(t), isTrue, reason: 'licence puis connexion puis accueil');
    expect(find.byType(AccueilScreen), findsOneWidget);
    expect(prefs.getString('local_ip'), _ip);
    expect(app.serveur.recuesSur('/licence/find'), isNotEmpty);

    // 5. Modes de paiement de cet appareil : valeurs d'une installation neuve (comme l'ancienne application : espèces
    //    non cochées), puis espèces cochées comme dans Réglages › Ventes ; vente terminée, envoyée avec le nom saisi.
    final reglages = Provider.of<SettingsProvider>(t.element(find.byType(AccueilScreen)), listen: false);
    expect(reglages.enabledPaymentMethodIds, ['10', '7', '9', '8', '3'], reason: 'valeurs par défaut d\'une installation neuve');
    await reglages.togglePaymentMethod('1', true);
    await app.ouvrirMenu(t, ListPresentation.dashboard, 'prevente');
    expect(await ajouterAuPanier(t, app, nomCourt(3)), isTrue);
    await app.attendre(t, const Duration(seconds: 2));
    await validerEncaissementEspeces(t, app);
    await app.attendre(t, const Duration(seconds: 3));
    expect(c.clotures, 1, reason: 'vente terminée');
    for (final r in app.serveur.recues) {
      expect(r.poste, 'Caisse%20V3', reason: '$r');
    }
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  group('Bandeau « Ancienne application installée »', () {
    final bandeau = find.byKey(const Key('bandeau_ancienne_appli'));

    testWidgets('ancienne application installée : bandeau sur la connexion, « Compris » → plus jamais', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      var detections = 0;
      AncienneAppli.detecteur = () async {
        detections++;
        return true;
      };
      final app = AppE2E();
      await app.preparer();
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      expect(await app.attendreQue(t, bandeau), isTrue);
      expect(find.text(AncienneAppli.message), findsOneWidget);
      expect(detections, 1);
      await _toucher(t, app, find.byKey(const Key('bandeau_ancienne_appli_compris')));
      expect(bandeau, findsNothing);
      expect((await SharedPreferences.getInstance()).getBool(AncienneAppli.prefVu), isTrue);
      // La connexion marche comme avant, bandeau ou non.
      expect(await app.seConnecter(t), isTrue);
      await app.fermer(t);

      // Lancement suivant : plus de bandeau, plus de détection.
      await app.lancer(t);
      expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
      await app.attendre(t);
      expect(bandeau, findsNothing);
      expect(detections, 1);
      await app.fermer(t);
    });

    testWidgets('ancienne application absente, ou détection impossible : aucun bandeau, connexion normale', (t) async {
      TailleEcran.sunmiV2s.appliquer(t);
      for (final d in <Future<bool> Function()>[() async => false, () async => throw Exception('canal absent')]) {
        AncienneAppli.detecteur = d;
        final app = AppE2E();
        await app.preparer();
        await app.lancer(t);
        expect(await app.attendreQue(t, find.byType(ConnexionScreen)), isTrue);
        await app.attendre(t);
        expect(bandeau, findsNothing);
        expect(find.byType(LancementScreen), findsNothing);
        expect(await app.seConnecter(t), isTrue);
        expect(t.takeException(), isNull);
        await app.fermer(t);
      }
    });
  });
}
