// Outil (hors CI) : écrit test/references/tickets/*.txt à partir de test/outils/tickets_vente_fictifs.dart.
// `flutter test test/outils/generer_tickets_reference_test.dart` ; relire chaque fichier avant de le valider.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'tickets_vente_fictifs.dart';

void main() {
  test('génère les tickets de référence', () {
    for (final e in ticketsReference().entries) {
      File('test/references/tickets/${e.key}.txt').writeAsStringSync('${e.value.texte}\n');
    }
  });
}
