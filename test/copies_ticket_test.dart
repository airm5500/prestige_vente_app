// 4.10.3 — unitaires de la pause entre les copies (lib/ventes/common/copies_ticket.dart) : 0 copie → rien ; 1 → une
// impression, aucun dialogue ; N → exactement N-1 dialogues « Ticket suivant (i/N) », jamais avant la copie 1 ;
// Imprimer par défaut (focus) ; « Arrêter » et le retour Android annulent les copies restantes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';

Future<BuildContext> _ctx(WidgetTester t) async {
  late BuildContext c;
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
    c = ctx;
    return const Scaffold();
  })));
  return c;
}

void main() {
  final pause = find.byKey(const ValueKey('ticket-suivant'));

  testWidgets('0 copie : rien ; 1 copie : une impression, aucun dialogue', (t) async {
    final c = await _ctx(t);
    var n = 0;
    expect(await imprimerCopiesAvecPause(c, 0, () async => n++), 0);
    expect(n, 0);
    final f = imprimerCopiesAvecPause(c, 1, () async => n++);
    await t.pumpAndSettle();
    expect(pause, findsNothing);
    expect(await f, 1);
    expect(n, 1);
  });

  testWidgets('3 copies : copie 1, pause 2/3, copie 2, pause 3/3, copie 3 ; Imprimer a le focus', (t) async {
    final c = await _ctx(t);
    final journal = <String>[];
    final f = imprimerCopiesAvecPause(c, 3, () async => journal.add('copie'));
    await t.pumpAndSettle();
    expect(journal, ['copie'], reason: 'copie 1 sans pause');
    expect(find.text('Ticket suivant (2/3)'), findsOneWidget);
    expect(find.text('Coupez le ticket, puis imprimez le suivant.'), findsOneWidget);
    expect(find.text('Arrêter'), findsOneWidget);
    expect(Focus.of(t.element(find.text('Imprimer'))).hasFocus, isTrue, reason: 'Imprimer par défaut');
    await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
    await t.pumpAndSettle();
    expect(journal, ['copie', 'copie']);
    expect(find.text('Ticket suivant (3/3)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ticket-suivant-imprimer')));
    await t.pumpAndSettle();
    expect(await f, 3);
    expect(pause, findsNothing);
  });

  testWidgets('« Arrêter » à 2/3 : une seule copie, aucune autre pause', (t) async {
    final c = await _ctx(t);
    var n = 0;
    final f = imprimerCopiesAvecPause(c, 3, () async => n++);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ticket-suivant-arreter')));
    await t.pumpAndSettle();
    expect(await f, 1);
    expect(n, 1);
    expect(pause, findsNothing);
  });

  testWidgets('retour Android sur la pause = Arrêter ; le dialogue ne se ferme pas en touchant à côté', (t) async {
    final c = await _ctx(t);
    var n = 0;
    final f = imprimerCopiesAvecPause(c, 2, () async => n++);
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(pause, findsOneWidget, reason: 'barrière non refermable');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(await f, 1);
    expect(n, 1);
  });
}
