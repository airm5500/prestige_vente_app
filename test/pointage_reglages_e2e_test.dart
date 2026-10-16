// 4.4.0 — E2E (application entière, faux serveur) des réglages du pointage signalés par le pharmacien :
// - « Photo de contrôle » (Paramètres › Équipe & pointage) : « je coche, je sors du menu, j'y reviens : décoché ».
//   Non reproduit (le réglage est enregistré sur l'appareil) : verrouillé ici, aller-retour complet par l'accueil,
//   dans les deux sens, et relu après un redémarrage de l'application ;
// - « Seulement les pointages sans photo » (écran Photos de contrôle) : désormais mémorisé, lui aussi.
// Aucune donnée réelle : employés et photos fictifs, caméra simulée.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/photo_controle_screen.dart';
import 'package:prestige_vente_app/services/pin_securise.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'outils/app_e2e.dart';

class _Code extends CodeAdmin {
  @override
  Future<Duration?> attenteRestante() async => null;
  @override
  Future<VerificationPin> verifier(String saisie) async => saisie == '4827' ? VerificationPin.accepte : VerificationPin.refuse;
}

class _Camera implements CameraControle {
  @override
  Future<SessionCamera> ouvrir() async => throw const CameraIndisponible(MotifSansPhoto.cameraAbsente);
}

void main() {
  late RegistrePhotosPointage registre;

  setUp(() {
    final avant = CodeAdmin.instance;
    CodeAdmin.instance = _Code();
    registre = RegistrePhotosPointage(stockage: StockagePhotosMemoire());
    PhotoControle.instance = PhotoControle(camera: _Camera(), registre: registre);
    addTearDown(() {
      CodeAdmin.instance = avant;
      PhotoControle.instance = null;
    });
  });

  Future<void> ouvrirEquipe(WidgetTester t, AppE2E app, {bool code = true}) async {
    await t.tap(find.text('Réglages').last);
    await app.attendre(t, const Duration(seconds: 1));
    await app.defilerJusqua(t, find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
    await t.tap(find.byKey(Key('rubrique_${Rubrique.equipe.name}')));
    await app.attendre(t, const Duration(seconds: 1));
    if (code) {
      expect(find.byKey(const Key('pin_admin_saisie')), findsOneWidget);
      await t.enterText(find.byKey(const Key('pin_admin_saisie')), '4827');
      await t.tap(find.text('Valider'));
      await app.attendre(t, const Duration(seconds: 1));
    }
    await app.defilerJusqua(t, find.byKey(const Key('rh_reglage_photo')));
  }

  bool photoCochee(WidgetTester t) => t.widget<SwitchCard>(find.byKey(const Key('rh_reglage_photo'))).value;

  Future<void> retourAccueil(WidgetTester t, AppE2E app) async {
    await app.retour(t); // Équipe → Réglages
    await app.retour(t); // Réglages → accueil
  }

  testWidgets('Photo de contrôle : décochée / recochée, sortie du menu et retour, puis redémarrage : valeur gardée', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    final app = AppE2E();
    await app.preparer();
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);

    await ouvrirEquipe(t, app);
    expect(photoCochee(t), isTrue, reason: 'activée par défaut');
    for (final attendu in [false, true, false]) {
      await t.tap(find.descendant(of: find.byKey(const Key('rh_reglage_photo')), matching: find.byType(Switch)));
      await app.attendre(t, const Duration(milliseconds: 500));
      expect(photoCochee(t), attendu);
      await retourAccueil(t, app);
      await ouvrirEquipe(t, app);
      expect(photoCochee(t), attendu, reason: 'relu après être sorti du menu et revenu');
    }
    expect((await ReglagesPointageTerminal.charger()).photoBadge, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('rh_photo_badge_v1'), isFalse);

    // Redémarrage de l'application (mêmes préférences) : toujours décochée.
    await app.fermer(t);
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await ouvrirEquipe(t, app);
    expect(photoCochee(t), isFalse, reason: 'gardée après redémarrage');
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });

  testWidgets('Photos de contrôle : filtre « Seulement les pointages sans photo » mémorisé (sortie, retour, redémarrage)', (t) async {
    TailleEcran.sunmiV2s.appliquer(t);
    await registre.ajouter(id: 'P1', employeId: 'E1', employeNom: 'TEST Employé A', lu: DateTime(2026, 10, 16, 8, 2), sens: 'Entrée', resultat: PhotoPrise(img.encodeJpg(img.Image(width: 8, height: 8))));
    await registre.ajouter(
        id: 'P2', employeId: 'E2', employeNom: 'TEST Employé B', lu: DateTime(2026, 10, 16, 8, 5), sens: 'Entrée',
        resultat: const PhotoAbsente(MotifSansPhoto.delaiDepasse, 'caméra frontale non ouverte en 10 s'));
    final app = AppE2E();
    await app.preparer();
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);

    Future<void> ouvrirPhotos({bool code = true}) async {
      await ouvrirEquipe(t, app, code: code);
      await app.defilerJusqua(t, find.byKey(const Key('rh_reglage_photos')));
      await t.tap(find.byKey(const Key('rh_reglage_photos')));
      await app.attendre(t, const Duration(seconds: 1));
      expect(find.byType(PhotosPointageScreen), findsOneWidget);
    }

    bool filtre() => t.widget<SwitchListTile>(find.byKey(const Key('photos_filtre_sans'))).value;

    await ouvrirPhotos();
    expect(filtre(), isFalse);
    expect(find.text('TEST Employé A · Entrée'), findsOneWidget);
    expect(find.text('Détail : caméra frontale non ouverte en 10 s'), findsOneWidget, reason: 'motif détaillé (4.4.0)');
    await t.tap(find.byKey(const Key('photos_filtre_sans')));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect(find.text('TEST Employé A · Entrée'), findsNothing);
    await app.retour(t); // Photos → Équipe
    await retourAccueil(t, app);
    await ouvrirPhotos();
    expect(filtre(), isTrue, reason: 'filtre gardé après être sorti et revenu');
    expect(find.text('TEST Employé A · Entrée'), findsNothing);
    expect(find.text('TEST Employé B · Entrée'), findsOneWidget);

    await app.fermer(t);
    await app.lancer(t);
    expect(await app.seConnecter(t, login: DonneesFictives.admin, motDePasse: DonneesFictives.motDePasseAdmin), isTrue);
    await ouvrirPhotos();
    expect(filtre(), isTrue, reason: 'gardé après redémarrage');
    await t.tap(find.byKey(const Key('photos_filtre_sans')));
    await app.attendre(t, const Duration(milliseconds: 500));
    expect((await SharedPreferences.getInstance()).getBool(prefFiltreSansPhoto), isFalse);
    expect(t.takeException(), isNull);
    await app.fermer(t);
  });
}
