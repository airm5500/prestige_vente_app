// lib/pointage/pointage_export.dart
// Pointage LOCAL (empreinte / PIN) : ces pointages restent sur l'appareil, ils ne sont PAS envoyés à Prestige.
// Messages communs aux écrans du pointage local et export CSV (les données ne sont jamais perdues : un administrateur
// peut les exporter et les reprendre dans Prestige, RH › Présence du jour › Pointage manuel).
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';

/// Titre de l'écran et libellé du menu (accueil).
const String titrePointageLocal = 'Pointage local';

/// Avertissement affiché en tête du pointage local.
const String avertissementPointageLocal =
    'Ces pointages restent sur cet appareil : ils ne sont PAS envoyés à Prestige et n\'apparaissent pas dans '
    '« Présence du jour ». Pour pointer dans Prestige : Accueil › Équipe › Pointage présence.';

/// Suffixe du message de confirmation d'un pointage local.
const String suffixeEnregistrementLocal = ' (sur cet appareil, non envoyé à Prestige)';

String _champ(String v) => v.contains(RegExp('[;"\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// CSV (séparateur « ; », lisible par un tableur) des pointages locaux, du plus ancien au plus récent.
String csvPointagesLocaux(List<Employee> employes, List<PointageRecord> pointages) {
  final parId = {for (final e in employes) e.id: e};
  final d = DateFormat('yyyy-MM-dd');
  final h = DateFormat('HH:mm');
  final b = StringBuffer('Date;Heure;Matricule;Employé;Type;Méthode;Appareil;Envoyé à Prestige\n');
  for (final r in [...pointages]..sort((a, b) => a.time.compareTo(b.time))) {
    final e = parId[r.employeeId];
    b.writeln([
      d.format(r.time),
      h.format(r.time),
      e?.matricule ?? '',
      e?.name ?? r.employeeId,
      r.type.label,
      r.method.label,
      r.device,
      'non',
    ].map(_champ).join(';'));
  }
  return b.toString();
}
