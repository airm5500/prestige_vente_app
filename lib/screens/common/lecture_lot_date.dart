// lib/screens/common/lecture_lot_date.dart
// Lecture du LOT et de la PÉREMPTION d'une boîte, par la caméra (DataMatrix) ou par photo de l'étiquette — UN seul
// chemin pour « Mise à jour péremption » et la réception des BL (4.11.0, plan du pharmacien du 08/11 : « lecture
// datamatrix : utiliser le même principe que la mise à jour péremption ; on récupère juste le lot et la date ; la photo
// tremble trop »). Sorti de ExpirationUpdateScreen, sans changement de comportement pour cet écran :
//   - caméra : haute définition (1280×720), zoom automatique et bouton « Zoom ×2 », tous les codes des boîtes ;
//     un code-barres sans lot ni date n'est pas pris : message sur l'image, la lecture continue jusqu'au DataMatrix ;
//   - photo : capture guidée (cadre, netteté, stabilité, lampe, photo prise seule quand l'image est bonne), lecture
//     des codes de la photo (un DataMatrix lu = lot et date sûrs), sinon lecture du texte puis confirmation OBLIGATOIRE
//     des valeurs (« Vérifiez avec la boîte »), « Reprendre la photo » possible.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prestige_vente_app/screens/common/camera_scan_screen.dart';
import 'package:prestige_vente_app/screens/common/guided_capture_screen.dart';
import 'package:prestige_vente_app/services/datamatrix_parser.dart';
import 'package:prestige_vente_app/services/label_text_parser.dart';
import 'package:prestige_vente_app/services/ocr_service.dart';
import 'package:prestige_vente_app/services/saisie_peremption.dart';
import 'package:prestige_vente_app/utils/constants.dart';

/// Réglages de la caméra pour lire lot et date.
const optionsScanLotDate = (
  produit: true,
  hauteDefinition: true,
  aide: 'Visez le petit carré (DataMatrix) de la boîte, à 10-15 cm.\nZoom ×2 en haut si le code est petit.',
);

/// Lot / date : un code lu sans lot ni date (EAN de la boîte) n'est pas ignoré en silence : message sur l'image, la
/// lecture continue jusqu'au DataMatrix.
String? refusLotDate(String valeur) {
  final d = DataMatrixParser.parse(valeur);
  if (d != null && (d.lotCandidates.isNotEmpty || d.expiryCandidates.isNotEmpty || d.invalidExpiry)) return null;
  return 'Code-barres lu, sans lot ni date. Visez le DataMatrix (petit carré).';
}

/// Caméra « lot / date » : contenu brut du DataMatrix lu, null si annulé.
Future<String?> scannerLotDate(BuildContext context, {String title = 'Scanner le DataMatrix (lot / date)'}) => CameraScanScreen.open(
      context,
      title: title,
      produit: optionsScanLotDate.produit,
      hauteDefinition: optionsScanLotDate.hauteDefinition,
      aide: optionsScanLotDate.aide,
      verifier: refusLotDate,
    );

/// Photo de l'étiquette → lot et date, confirmés par l'opérateur (ou lus dans un DataMatrix de la photo).
/// [depuisDataMatrix] : vrai quand le DataMatrix de la photo a été lu (valeurs sûres, [brut] = son contenu).
typedef LotDatePhoto = ({DataMatrixData donnees, bool depuisDataMatrix, String brut});

/// Photo de l'étiquette (capture guidée) : lot et date confirmés, null si annulé ou illisible (message affiché).
/// [lecteurEtiquette] / [lecteurTexte] : remplaçables pour les tests. [occupe] : début / fin de la lecture.
/// [reprendre] : action « Reprendre » du message « Ni lot ni date lisibles ».
Future<LotDatePhoto?> photoLotDate(
  BuildContext context, {
  Future<LectureEtiquette?> Function(BuildContext context)? lecteurEtiquette,
  Future<List<String>?> Function(ImageSource source)? lecteurTexte,
  void Function(bool occupe)? occupe,
  VoidCallback? reprendre,
}) async {
  while (true) {
    if (!context.mounted) return null;
    List<String>? lines;
    var codes = const <String>[];
    occupe?.call(true);
    try {
      if (lecteurEtiquette != null || lecteurTexte == null) {
        final r = await (lecteurEtiquette ?? (ctx) => GuidedCaptureScreen.openEtiquette(ctx))(context);
        lines = r?.lignes;
        codes = r?.codes ?? const [];
      } else {
        lines = await lecteurTexte(ImageSource.camera);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(OcrService.friendlyError(e)),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ));
      }
    }
    occupe?.call(false);
    if (!context.mounted || lines == null) return null;

    // DataMatrix de la boîte présent sur la photo → lot et date GS1, sûrs (comme un scan).
    final brut = codes.where((c) => refusLotDate(c) == null).firstOrNull;
    final dm = brut == null ? null : DataMatrixParser.parse(brut);
    if (dm != null) {
      Constants.showSnackBar(context, 'DataMatrix lu sur la photo : lot et date repris.');
      return (donnees: dm, depuisDataMatrix: true, brut: brut!);
    }

    final label = LabelTextParser.parse(lines);
    if (label.lotCandidates.isEmpty && label.expiryCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Ni lot ni date lisibles. Cadrez uniquement LOT et EXP, à plat et bien éclairés.'),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 6),
        action: reprendre == null ? null : SnackBarAction(label: 'Reprendre', textColor: Colors.white, onPressed: reprendre),
      ));
      return null;
    }

    final confirmed = await showDialog<({String lot, DateTime? expiry, bool retake})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfirmationLotDate(label: label),
    );
    if (confirmed == null || !context.mounted) return null;
    if (confirmed.retake) continue;

    // Valeurs confirmées par l'opérateur : traitées comme un scan fiable.
    return (
      donnees: DataMatrixData(
        raw: lines.join('\n'),
        format: DataMatrixFormat.ocrLabel,
        gtin: label.gtin,
        lotCandidates: confirmed.lot.isEmpty ? const [] : [confirmed.lot],
        lotCertain: confirmed.lot.isNotEmpty,
        expiryCandidates: confirmed.expiry == null ? const [] : [confirmed.expiry!],
        expiryCertain: confirmed.expiry != null,
      ),
      depuisDataMatrix: false,
      brut: '',
    );
  }
}

/// Confirmation obligatoire des valeurs lues par photo : l'OCR peut se tromper (0/O, 1/I, 5/S...). Rien n'est
/// enregistré sans validation de l'opérateur.
class ConfirmationLotDate extends StatefulWidget {
  final LabelData label;
  const ConfirmationLotDate({super.key, required this.label});

  @override
  State<ConfirmationLotDate> createState() => _ConfirmationLotDateState();
}

class _ConfirmationLotDateState extends State<ConfirmationLotDate> {
  late final _lot = TextEditingController(text: widget.label.lotCandidates.isEmpty ? '' : widget.label.lotCandidates.first);
  late final _date = TextEditingController(
    text: widget.label.expiryCandidates.isEmpty ? '' : formaterDatePeremption(widget.label.expiryCandidates.first),
  );
  String? _dateError;

  @override
  void dispose() {
    _lot.dispose();
    _date.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _date.text.trim();
    DateTime? expiry;
    if (text.isNotEmpty) {
      expiry = lireDatePeremption(text);
      if (expiry == null) {
        setState(() => _dateError = 'Format attendu : JJ/MM/AAAA');
        return;
      }
    }
    Navigator.of(context).pop((lot: _lot.text.trim().toUpperCase(), expiry: expiry, retake: false));
  }

  Widget _chips<T>(List<T> values, String Function(T) format, void Function(T) onTap) {
    if (values.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      children: [for (final v in values) ActionChip(label: Text(format(v)), onPressed: () => onTap(v))],
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final warn = TextStyle(color: Colors.orange.shade900, fontSize: 12);
    return AlertDialog(
      title: const Text('Vérifiez avec la boîte'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparez chaque caractère avec l\'emballage avant de valider.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _lot,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'N° de Lot', border: OutlineInputBorder()),
            ),
            if (label.lotCandidates.isNotEmpty && !label.lotFromLabel)
              Text('Lot proposé sans libellé "LOT" : à vérifier.', style: warn),
            _chips<String>(label.lotCandidates, (v) => v, (v) => setState(() => _lot.text = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: 'Date de péremption (JJ/MM/AAAA)',
                border: const OutlineInputBorder(),
                errorText: _dateError,
              ),
            ),
            if (label.expiryCandidates.isNotEmpty && !label.expiryFromLabel)
              Text('Date déduite sans libellé "EXP" : à vérifier.', style: warn),
            _chips<DateTime>(label.expiryCandidates, formaterDatePeremption, (d) => setState(() => _date.text = formaterDatePeremption(d))),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Texte lu sur la photo', style: TextStyle(fontSize: 13)),
              children: [
                for (final l in label.rawLines)
                  Align(alignment: Alignment.centerLeft, child: Text(l, style: const TextStyle(fontSize: 12))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.of(context).pop((lot: '', expiry: null, retake: true)),
          child: const Text('Reprendre la photo'),
        ),
        ElevatedButton(onPressed: _confirm, child: const Text('Valider')),
      ],
    );
  }
}
