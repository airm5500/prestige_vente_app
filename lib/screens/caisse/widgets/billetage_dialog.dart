// lib/screens/caisse/widgets/billetage_dialog.dart
// 09/11/2025 02:20 (Amélioration Focus et Saisie)
// Refonte : page plein écran en présentations A/B/C, nombres de billets bornés,
// total plafonné, confirmation avant la clôture (définitive), pas de double envoi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/models/caisse_models.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Une ligne du billetage : clé envoyée au serveur, libellé, valeur unitaire.
/// Pour « Autres (Pièces) » on saisit directement un montant (valeur 1).
typedef _Coupure = ({String key, String label, int value, int maxDigits});

/// Bornes de saisie.
class BilletageLimits {
  BilletageLimits._();

  /// Nombre maximal de billets d'une même coupure.
  static const int maxBillets = 99999;

  /// Montant maximal des pièces et du total compté.
  static const int maxMontant = 999999999;
}

/// Saisie du billetage avant la clôture de caisse (page plein écran).
class BilletageDialog extends StatefulWidget {
  final ClotureData clotureData;

  /// Présentation transmise par l'écran Caisse (sinon celle de l'appareil).
  final ListPresentation? presentation;

  const BilletageDialog({super.key, required this.clotureData, this.presentation});

  @override
  State<BilletageDialog> createState() => _BilletageDialogState();
}

class _BilletageDialogState extends State<BilletageDialog> with PresentationAware {
  static const List<_Coupure> _coupures = [
    (key: 'dixMille', label: '10 000 F', value: 10000, maxDigits: 5),
    (key: 'cinqMille', label: '5 000 F', value: 5000, maxDigits: 5),
    (key: 'deuxMille', label: '2 000 F', value: 2000, maxDigits: 5),
    (key: 'mille', label: '1 000 F', value: 1000, maxDigits: 5),
    (key: 'cinqCent', label: '500 F', value: 500, maxDigits: 5),
    (key: 'autre', label: 'Autres (Pièces)', value: 1, maxDigits: 9),
  ];

  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _controllers = [for (final _ in _coupures) TextEditingController(text: '0')];
  late final List<FocusNode> _focusNodes = [for (final _ in _coupures) FocusNode()];

  int _totalCalcule = 0;
  bool _busy = false;
  String? _error;

  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    for (var i = 0; i < _coupures.length; i++) {
      _controllers[i].addListener(_calculateTotal);
      _setupFocusNodeSelection(_focusNodes[i], _controllers[i]);
    }
    // Focus automatique sur le premier champ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(_focusNodes.first);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // Sélection automatique du contenu à l'entrée dans un champ
  void _setupFocusNodeSelection(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
        });
      }
    });
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int _subtotal(int i) => _parse(_controllers[i]) * _coupures[i].value;

  void _calculateTotal() {
    var total = 0;
    for (var i = 0; i < _coupures.length; i++) {
      total += _subtotal(i);
    }
    if (total != _totalCalcule) setState(() => _totalCalcule = total);
  }

  String? _validate(int i, String? val) {
    final t = (val ?? '').trim();
    if (t.isEmpty) return 'Requis';
    final n = int.tryParse(t);
    if (n == null || n < 0) return 'Nombre invalide';
    final max = _coupures[i].value == 1 ? BilletageLimits.maxMontant : BilletageLimits.maxBillets;
    if (n > max) return 'Max ${Constants.formatNumber(max)}';
    return null;
  }

  String _signed(int v) => '${v > 0 ? '+' : ''}${Constants.formatNumber(v)}';

  String _ecartLabel(int ecart) => ecart == 0 ? 'Caisse juste' : (ecart > 0 ? 'Excédent' : 'Manquant');

  Future<void> _submit() async {
    if (_busy) return;
    final provider = Provider.of<CaisseProvider>(context, listen: false);
    if (provider.isLoading) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _error = 'Corrigez les champs en rouge.');
      return;
    }
    if (_totalCalcule > BilletageLimits.maxMontant) {
      setState(() => _error = 'Total trop élevé : vérifiez le nombre de billets saisis.');
      return;
    }

    // Confirmation : la clôture est définitive.
    final ecart = _totalCalcule - widget.clotureData.solde;
    FocusScope.of(context).unfocus();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirmer la clôture'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DetailLine('Total Compté', Constants.formatNumber(_totalCalcule), bold: true),
          DetailLine('Solde Théorique', Constants.formatNumber(widget.clotureData.solde)),
          DetailLine('Écart', '${_signed(ecart)} (${_ecartLabel(ecart)})', bold: true),
          const SizedBox(height: 8),
          if (_totalCalcule == 0)
            const Text('Attention : aucun billet ni pièce compté.', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          if (ecart != 0 && _totalCalcule != 0)
            const Text('Attention : le montant compté ne correspond pas au solde théorique.',
                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('La clôture est définitive.', style: TextStyle(color: Pal.muted)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Corriger')),
          ElevatedButton(style: navyButton, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    final billetage = <String, int>{
      for (var i = 0; i < _coupures.length; i++) _coupures[i].key: _parse(_controllers[i]),
    };

    setState(() => _busy = true);
    bool success = false;
    try {
      success = await provider.cloturerCaisse(billetage);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (success) {
      Navigator.of(context).pop(true); // Ferme le billetage
    } else {
      setState(() => _error = provider.errorMessage ?? 'Échec de la clôture de la caisse.');
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<CaisseProvider>(context);
    final locked = _busy || provider.isLoading;
    final solde = widget.clotureData.solde;
    final ecart = _totalCalcule - solde;
    final ecartColor = ecart == 0 ? AppColors.success : AppColors.error;
    final guided = style == ListPresentation.guided;
    final compact = style == ListPresentation.compact;

    return PopScope(
      canPop: !locked,
      child: PresentationScaffold(
        style: style,
        title: 'Billetage de Clôture',
        subtitle: orDash(widget.clotureData.userFullName),
        actions: (_) => const [],
        steps: StepsBar(active: _totalCalcule == 0 ? 0 : 1, steps: [
          (title: 'Compter', detail: 'billets et pièces', onTap: null),
          (title: 'Vérifier', detail: _ecartLabel(ecart).toLowerCase(), onTap: null),
          (title: 'Clôturer', detail: 'définitif', onTap: null),
        ]),
        header: [
          Row(children: [
            Expanded(child: HeaderFigure(Constants.formatNumber(solde), 'Solde Théorique')),
            const SizedBox(width: 8),
            Expanded(child: HeaderFigure(Constants.formatNumber(_totalCalcule), 'Total Compté')),
            const SizedBox(width: 8),
            Expanded(child: HeaderFigure(_signed(ecart), 'Écart', highlight: ecart != 0)),
          ]),
        ],
        compactHeader: [
          LightFigures([
            (Constants.formatNumber(solde), 'Solde théorique', Pal.navy),
            (Constants.formatNumber(_totalCalcule), 'Total compté', Pal.ink),
            (_signed(ecart), 'Écart', ecartColor),
          ]),
        ],
        body: Form(
          key: _formKey,
          child: ListView(
            padding: compact ? const EdgeInsets.only(top: 8, bottom: 24) : const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (locked) const LinearProgressIndicator(minHeight: 2),
              if (compact) ...[
                for (var i = 0; i < _coupures.length; i++) _buildBilletRow(i, compact: true),
                _totalsBlock(ecart, ecartColor, compact: true),
              ] else ...[
                SoftCard(
                  band: guided ? Pal.navy : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('Nombre de billets par coupure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
                    const Text('Pour les pièces, saisissez le montant total.', style: TextStyle(fontSize: 13, color: Pal.muted)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _coupures.length; i++) _buildBilletRow(i),
                  ]),
                ),
                const SizedBox(height: 12),
                SoftCard(band: guided ? ecartColor : null, child: _totalsBlock(ecart, ecartColor)),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Message d'erreur toujours visible, juste au-dessus du bouton.
              if (_error != null) _errorBanner(_error!),
              Row(children: [
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: outlineButton,
                    onPressed: locked ? null : () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: guided ? amberButton : navyButton,
                      icon: locked ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock),
                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Valider la Clôture')),
                      onPressed: locked ? null : _submit,
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDE7E7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF5B5B5)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Color(0xFF9B1C1C)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF9B1C1C), fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _totalsBlock(int ecart, Color ecartColor, {bool compact = false}) => Padding(
        padding: compact ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _totalLine('Total Compté', Constants.formatNumber(_totalCalcule), Pal.ink),
          _totalLine('Écart', _signed(ecart), ecartColor),
          Text(_ecartLabel(ecart), textAlign: TextAlign.end, style: TextStyle(color: ecartColor, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _totalLine(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Pal.ink, fontSize: 15))),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
            ),
          ),
        ]),
      );

  Widget _buildBilletRow(int i, {bool compact = false}) {
    final c = _coupures[i];
    final last = i == _coupures.length - 1;
    final pieces = c.value == 1;
    return Container(
      padding: compact ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : const EdgeInsets.symmetric(vertical: 6),
      decoration: compact ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF1F5)))) : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(c.label, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
          ),
        ),
        SizedBox(
          width: pieces ? 116 : 92,
          child: TextFormField(
            key: Key('billet_${c.key}'),
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            enabled: !_busy,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
              hintText: pieces ? 'Montant' : 'Nombre',
              errorMaxLines: 2,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(c.maxDigits)],
            validator: (val) => _validate(i, val),
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            // Le dernier champ valide le formulaire
            onFieldSubmitted: (_) => last ? _submit() : FocusScope.of(context).requestFocus(_focusNodes[i + 1]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(Constants.formatNumber(_subtotal(i)), style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}
