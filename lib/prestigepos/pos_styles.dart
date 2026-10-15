// lib/prestigepos/pos_styles.dart
// PrestigePOS — boutons aux couleurs de la charte (bleu nuit / ambre), texte selon le thème de l'appli
// (police du thème, taille de texte du système respectée).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';

final ButtonStyle posBoutonBleu = ElevatedButton.styleFrom(
  backgroundColor: Pal.navy,
  foregroundColor: Colors.white,
  minimumSize: const Size(64, 48),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

final ButtonStyle posBoutonAmbre = ElevatedButton.styleFrom(
  backgroundColor: Pal.amber,
  foregroundColor: Pal.onAmber,
  minimumSize: const Size(64, 48),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

final ButtonStyle posBoutonContour = OutlinedButton.styleFrom(
  foregroundColor: Pal.navy,
  minimumSize: const Size(64, 48),
  side: const BorderSide(color: Color(0xFFC5D0DE)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);
