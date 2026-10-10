// lib/parametres/rubriques_pages.dart
// Réglages : pages des rubriques (Impression, Ventes, Stock & contrôles, Apparence, Équipe & pointage,
// Sécurité, Licence & appareil). Les interrupteurs et choix s'appliquent immédiatement (mêmes clés
// de stockage que la Configuration d'origine).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/models/officine.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/api/models/user.dart';
import 'package:prestige_vente_app/interface_version.dart';
import 'package:prestige_vente_app/ordonnances/banc_essai/banc_essai_screen.dart';
import 'package:prestige_vente_app/ordonnances/o2/lecture_o2.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/pointage/pointage_logic.dart';
import 'package:prestige_vente_app/pointage/pointage_models.dart';
import 'package:prestige_vente_app/pointage/pointage_repository.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/sale_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/reception/reception_logic.dart';
import 'package:prestige_vente_app/screens/auth/qr_code_preview_screen.dart';
import 'package:prestige_vente_app/screens/pointage/employees_screen.dart';
import 'package:prestige_vente_app/screens/pointage/fingerprint_diagnostic_screen.dart';
import 'package:prestige_vente_app/screens/pointage/pointage_report_screen.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/search_mode.dart';
import 'package:prestige_vente_app/ventes/ventes_version.dart';
import 'package:prestige_vente_app/widgets/pin_code_dialog.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

const _verified = 'Code administrateur vérifié';

// ---------------------------------------------------------------------------
// Impression
// ---------------------------------------------------------------------------

/// Ticket d'essai : aperçu en mode test, sinon imprimante Sunmi (message clair si absente).
Future<void> imprimerTicketEssai(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final auth = context.read<AuthProvider>();
  final messenger = ScaffoldMessenger.of(context);
  if (!settings.isTestPrintMode) {
    bool connected = false;
    try {
      connected = await SunmiPrinter.bindingPrinter() == true;
    } catch (_) {
      connected = false;
    }
    if (!context.mounted) return;
    if (!connected) {
      messenger.showSnackBar(const SnackBar(
        backgroundColor: Color(0xFFDC2626),
        content: Text('Aucune imprimante Sunmi détectée sur cet appareil. Activez le mode test pour voir un aperçu à l\'écran.'),
      ));
      return;
    }
  }
  final now = DateTime.now();
  final ref = 'ESSAI${DateFormat('yyMMddHHmm').format(now)}';
  try {
    await ReceiptService().printSaleTicket(
      context: context,
      officine: auth.officine ?? Officine(fullName: 'Ticket d\'essai', nomComplet: 'PRESTIGE VENTE'),
      saleSummary: SaleSummary(montant: 1000, montantNet: 1000, reference: ref),
      items: [
        SaleItemDetail(
          lgPREENREGISTREMENTDETAILID: 'essai',
          lgFAMILLEID: 'essai',
          strNAME: 'ARTICLE D\'ESSAI',
          intCIP: '0000000',
          intQUANTITY: 1,
          intPRICEUNITAIR: 1000,
          intPRICE: 1000,
          strREF: ref,
        ),
      ],
      paymentMethod: PaymentMethod(id: 'essai', name: 'Espèces'),
      currentUser: auth.user ?? User(userId: '', login: '', firstName: 'Essai', lastName: '', officineName: ''),
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      showQrCode: settings.showQrCodeOnSaleTicket,
      ticketCodeType: settings.ticketCodeType,
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(backgroundColor: Color(0xFFDC2626), content: Text('Impression impossible. Vérifiez l\'imprimante.')));
  }
}

class ImpressionPage extends StatefulWidget {
  final Future<void> Function(BuildContext) printTest;
  const ImpressionPage({super.key, required this.printTest});

  @override
  State<ImpressionPage> createState() => _ImpressionPageState();
}

class _ImpressionPageState extends State<ImpressionPage> {
  bool _printing = false;

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    await widget.printTest(context);
    if (!mounted) return;
    setState(() => _printing = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    return RubriquePage(
      title: Rubrique.impression.title,
      subtitle: 'Appliqué immédiatement',
      bottom: BottomBar(children: [
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            style: navyButton,
            onPressed: _printing ? null : _print,
            icon: const Icon(Icons.print),
            label: const FittedBox(child: Text('IMPRIMER UN TICKET D\'ESSAI')),
          ),
        ),
      ]),
      children: [
        const SectionLabel('Largeur du ticket'),
        Segmented<int>(options: const [(58, '58 mm'), (80, '80 mm')], value: s.paperWidth, onChanged: s.setPaperWidth),
        const SectionLabel('Type de code sur le ticket'),
        Segmented<String>(
          options: const [('QR_CODE', 'QR code'), ('BARCODE', 'Code-barres')],
          value: s.ticketCodeType,
          onChanged: s.setTicketCodeType,
        ),
        const SizedBox(height: 12),
        SwitchCard(
          title: 'Afficher le QR / code-barres (vente)',
          subtitle: 'Sur le ticket de vente comptant',
          value: s.showQrCodeOnSaleTicket,
          onChanged: s.setShowQrCodeOnSaleTicket,
        ),
        CounterCard(
          key: const Key('tickets_vente'),
          title: 'Tickets par vente',
          subtitle: 'Vente simple',
          value: s.numberOfTickets,
          min: 1,
          max: 3,
          onChanged: s.setNumberOfTickets,
        ),
        CounterCard(
          key: const Key('tickets_assurance'),
          title: 'Tickets par vente assurance',
          value: s.numberOfTicketsAssurance,
          min: 1,
          max: 3,
          onChanged: s.setNumberOfTicketsAssurance,
        ),
        SwitchCard(
          title: 'Mode test d\'impression',
          subtitle: 'Aperçu à l\'écran au lieu d\'imprimer',
          value: s.isTestPrintMode,
          onChanged: s.setTestPrintMode,
        ),
        ResetDefaultsButton(
          rubrique: 'Impression',
          detail: '58 mm, QR code, code non affiché sur la vente, 1 ticket (2 en assurance), mode test désactivé.',
          onReset: () async {
            await s.setPaperWidth(58);
            await s.setTicketCodeType('QR_CODE');
            await s.setShowQrCodeOnSaleTicket(false);
            await s.setNumberOfTickets(1);
            await s.setNumberOfTicketsAssurance(2);
            await s.setTestPrintMode(false);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ventes
// ---------------------------------------------------------------------------

class VentesPage extends StatefulWidget {
  const VentesPage({super.key});

  @override
  State<VentesPage> createState() => _VentesPageState();
}

class _VentesPageState extends State<VentesPage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || context.read<SettingsProvider>().localIp.isEmpty) return;
    setState(() => _loading = true);
    await context.read<SaleProvider>().fetchPaymentMethodsWithQr();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final methods = context.watch<SaleProvider>().paymentMethodsWithQr;
    return RubriquePage(
      title: Rubrique.ventes.title,
      subtitle: _verified,
      children: [
        const SettingCard(padding: EdgeInsets.symmetric(vertical: 4), child: VentesVersionTile()),
        const SectionLabel('Modes de paiement proposés'),
        if (s.localIp.isEmpty)
          const InfoBanner.warning('Veuillez d\'abord configurer l\'IP du serveur.')
        else if (_loading)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (methods.isEmpty)
          SettingCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Modes de paiement non chargés : le serveur n\'a pas répondu (Wifi, IP, serveur éteint).',
                  style: TextStyle(color: Color(0xFF7F1D1D))),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
              ),
            ]),
          )
        else ...[
          for (final m in methods)
            SettingCard(
              padding: EdgeInsets.zero,
              child: CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Pal.navy,
                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: m.qrCode != null ? const Text('QR configuré') : null,
                value: s.enabledPaymentMethodIds.contains(m.id),
                onChanged: (v) {
                  if (v != null) s.togglePaymentMethod(m.id, v);
                },
              ),
            ),
          LinkCard(
            icon: Icons.qr_code_2,
            title: 'Aperçu des QR codes de paiement',
            subtitle: 'Modes de paiement activés',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrCodePreviewScreen())),
          ),
        ],
        const SectionLabel('Assurance et produits'),
        CounterCard(
          key: const Key('max_tiers'),
          title: 'Tiers payants max (assurance)',
          value: s.maxTiersPayants,
          min: 1,
          max: 3,
          onChanged: s.setMaxTiersPayants,
        ),
        SwitchCard(title: 'Masquer les produits « RV »', value: s.hideRvProducts, onChanged: s.setHideRvProducts),
        const SectionLabel('Ordonnances'),
        const LectureO2Reglages(),
        LinkCard(
          key: const Key('banc_essai_ordonnances'),
          icon: Icons.science_outlined,
          title: 'Banc d\'essai ordonnances',
          subtitle: 'Mesure de la lecture sur vos images (rien n\'est envoyé)',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BancEssaiScreen())),
        ),
        ResetDefaultsButton(
          rubrique: 'Ventes',
          detail: '2 tiers payants max, produits « RV » masqués (la version des ventes et les modes de paiement ne changent pas).',
          onReset: () async {
            await s.setMaxTiersPayants(2);
            await s.setHideRvProducts(true);
          },
        ),
      ],
    );
  }
}

/// Interrupteurs de la nouvelle lecture des ordonnances (O2), désactivés par défaut.
class LectureO2Reglages extends StatefulWidget {
  const LectureO2Reglages({super.key});

  @override
  State<LectureO2Reglages> createState() => _LectureO2ReglagesState();
}

class _LectureO2ReglagesState extends State<LectureO2Reglages> {
  @override
  void initState() {
    super.initState();
    LectureO2.charger();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: LectureO2.actif,
        builder: (context, actif, _) => ValueListenableBuilder<bool>(
          valueListenable: LectureO2.ameliorerImage,
          builder: (context, image, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchCard(
              key: const Key('lecture_o2'),
              title: 'Nouvelle lecture des ordonnances (O2)',
              subtitle: 'Photo guidée de la page, zone des médicaments, lignes numérotées. '
                  'À activer seulement si le banc d\'essai donne un meilleur score.',
              value: actif,
              onChanged: LectureO2.definirActif,
            ),
            if (actif)
              SwitchCard(
                key: const Key('lecture_o2_image'),
                title: 'Améliorer l\'image (contraste, ombres)',
                subtitle: 'Mesurez-le aussi au banc d\'essai avant de l\'activer.',
                value: image,
                onChanged: LectureO2.definirAmeliorerImage,
              ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Stock & contrôles
// ---------------------------------------------------------------------------

class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  ReceptionSettings? _reception;

  @override
  void initState() {
    super.initState();
    ReceptionSettings.load().then((r) {
      if (mounted) setState(() => _reception = r);
    });
  }

  Future<void> _saveReception(ReceptionSettings r) async {
    setState(() => _reception = r);
    try {
      await r.save();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réglage de réception non enregistré.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final r = _reception;
    return RubriquePage(
      title: Rubrique.stock.title,
      subtitle: _verified,
      children: [
        const SectionLabel('Droits'),
        SwitchCard(
          title: 'Modifier le contrôle livraison',
          value: s.canEditDeliveryControl,
          onChanged: s.setCanEditDeliveryControl,
        ),
        SwitchCard(title: 'Modifier le pointage BL', value: s.canEditBlControl, onChanged: s.setCanEditBlControl),
        const SectionLabel('Comparaison stock BL'),
        Segmented<String>(
          options: const [('theorique', 'Théorique'), ('machine', 'Machine')],
          value: s.blStockComparisonMode,
          onChanged: s.setBlStockComparisonMode,
        ),
        const SectionLabel('Réception BL (cet appareil)'),
        if (r == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else ...[
          SettingCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SettingText('Péremption courte en dessous de'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in const [3, 6, 9, 12])
                  ChoiceChip(
                    label: Text('$m mois'),
                    selected: r.shortExpiryMonths == m,
                    onSelected: (_) => _saveReception(r.copyWith(shortExpiryMonths: m)),
                  ),
              ]),
            ]),
          ),
          SwitchCard(
            title: 'Valider l\'entrée en stock sur ce terminal',
            subtitle: 'Le droit « Entrée en stock » de l\'utilisateur est aussi vérifié par Prestige.',
            value: r.terminalValidation,
            onChanged: (v) => _saveReception(r.copyWith(terminalValidation: v)),
          ),
        ],
        ResetDefaultsButton(
          rubrique: 'Stock & contrôles',
          detail: 'contrôles modifiables, comparaison théorique, péremption courte à 6 mois, validation sur le terminal désactivée.',
          onReset: () async {
            await s.setCanEditDeliveryControl(true);
            await s.setCanEditBlControl(true);
            await s.setBlStockComparisonMode('theorique');
            await _saveReception(const ReceptionSettings());
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Apparence
// ---------------------------------------------------------------------------

class ApparencePage extends StatefulWidget {
  final ListPresentation initial;
  final Future<void> Function(BuildContext) openOrganiser;
  const ApparencePage({super.key, required this.initial, required this.openOrganiser});

  @override
  State<ApparencePage> createState() => _ApparencePageState();
}

class _ApparencePageState extends State<ApparencePage> {
  late ListPresentation _p = widget.initial;

  static String _detail(ListPresentation p) => switch (p) {
        ListPresentation.dashboard => 'Chiffres clés et cartes',
        ListPresentation.compact => 'Listes denses',
        ListPresentation.guided => 'Étapes, bouton ambre',
      };

  Future<void> _choose(ListPresentation p) async {
    setState(() => _p = p);
    await PresentationPrefs.save(p);
  }

  @override
  Widget build(BuildContext context) => RubriquePage(
        title: Rubrique.apparence.title,
        children: [
          const SectionLabel('Présentation de tous les menus'),
          for (final p in ListPresentation.values)
            SettingCard(
              padding: EdgeInsets.zero,
              child: RadioListTile<ListPresentation>(
                key: Key('presentation_${p.name}'),
                activeColor: Pal.navy,
                value: p,
                groupValue: _p,
                onChanged: (v) {
                  if (v != null) _choose(v);
                },
                title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_detail(p)),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text('Chaque menu peut toujours changer de présentation avec son bouton « Présentation ».',
                style: TextStyle(fontSize: 12.5, color: Pal.muted)),
          ),
          const SectionLabel('Accueil'),
          LinkCard(
            icon: Icons.dashboard_customize,
            title: 'Organiser l\'accueil',
            subtitle: 'Ordre, favoris et menus masqués',
            locked: true,
            onTap: () => widget.openOrganiser(context),
          ),
          const SettingCard(padding: EdgeInsets.symmetric(vertical: 4), child: InterfaceVersionTile()),
          const SectionLabel('Recherche'),
          const SearchModeSetting(),
        ],
      );
}

/// Recherche texte des produits, clients et tiers payants : « Commence par » / « Contient ».
class SearchModeSetting extends StatelessWidget {
  const SearchModeSetting({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SearchMode>(
        valueListenable: SearchModePrefs.mode,
        builder: (context, mode, _) => SettingCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SettingText('Recherche des produits, clients et tiers payants',
                subtitle: 'Les codes scannés ou tapés (CIP, EAN) cherchent toujours le produit exact.'),
            const SizedBox(height: 10),
            Segmented<SearchMode>(
              key: const Key('recherche_mode'),
              options: [for (final m in SearchMode.values) (m, m.label)],
              value: mode,
              onChanged: SearchModePrefs.save,
            ),
            const SizedBox(height: 8),
            Text(
              mode == SearchMode.contient
                  ? 'Le nom contient le texte tapé, mots dans l\'ordre (dès 3 caractères) : « doli 1000 » trouve « DOLIPRANE 1000MG ».'
                  : 'Le nom commence par le texte tapé : « doli » trouve « DOLIPRANE… », « 1000 » ne le trouve pas.',
              style: const TextStyle(fontSize: 12.5, color: Pal.muted),
            ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// Équipe & pointage
// ---------------------------------------------------------------------------

String pointageSummary(PointageSettings s) => switch (s.badgeMode) {
      BadgeMode.off => 'Empreinte / PIN selon l\'appareil',
      BadgeMode.only => 'Badge uniquement',
      BadgeMode.both => 'Badge ou empreinte / PIN',
    } +
    (s.badgeEnabled && s.pinAfterBadge ? ' · PIN après le badge' : '');

class EquipePage extends StatefulWidget {
  final PointageRepository repository;
  const EquipePage({super.key, required this.repository});

  @override
  State<EquipePage> createState() => _EquipePageState();
}

class _EquipePageState extends State<EquipePage> {
  PointageSettings _settings = const PointageSettings();
  DeviceCapability? _capability;

  @override
  void initState() {
    super.initState();
    widget.repository.loadSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    }).catchError((_) {});
  }

  /// Même dialogue que l'accueil du pointage (le code administrateur est déjà vérifié).
  Future<void> _editMethod() async {
    var draft = _settings;
    final saved = await showDialog<PointageSettings>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Méthode de pointage'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final m in BadgeMode.values)
                RadioListTile<BadgeMode>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.label),
                  value: m,
                  groupValue: draft.badgeMode,
                  onChanged: (v) => setLocal(() => draft = draft.copyWith(badgeMode: v)),
                ),
              if (draft.badgeEnabled)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Code PIN après le badge'),
                  subtitle: const Text('Empêche de pointer avec le badge d\'un collègue.'),
                  value: draft.pinAfterBadge,
                  onChanged: (v) => setLocal(() => draft = draft.copyWith(pinAfterBadge: v ?? false)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(draft), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await widget.repository.saveSettings(saved);
    if (mounted) setState(() => _settings = saved);
  }

  Future<void> _employees() async {
    _capability ??= await DeviceCapability.detect().catchError((_) => const DeviceCapability(mode: PointageMode.pinOrName));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeesScreen(repository: widget.repository, capability: _capability),
    ));
  }

  @override
  Widget build(BuildContext context) => RubriquePage(
        title: Rubrique.equipe.title,
        subtitle: _verified,
        children: [
          LinkCard(icon: Icons.tune, title: 'Méthode de pointage', subtitle: pointageSummary(_settings), onTap: _editMethod),
          LinkCard(
            icon: Icons.people,
            title: 'Employés',
            subtitle: 'Ajouter, horaires, code PIN, badge (code-barres, QR, NFC), empreinte',
            onTap: _employees,
          ),
          LinkCard(
            icon: Icons.insights,
            title: 'Rapport et analyse',
            subtitle: 'Présence, retards, heures, comportement',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PointageReportScreen(repository: widget.repository))),
          ),
          LinkCard(
            icon: Icons.fingerprint,
            title: 'Diagnostic du lecteur',
            subtitle: 'Vérifier le lecteur de cet appareil',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FingerprintDiagnosticScreen())),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Sécurité
// ---------------------------------------------------------------------------

class SecuritePage extends StatelessWidget {
  const SecuritePage({super.key});

  @override
  Widget build(BuildContext context) => RubriquePage(
        title: Rubrique.securite.title,
        subtitle: _verified,
        children: [
          LinkCard(
            icon: Icons.lock_reset,
            title: 'Modifier le code PIN administrateur',
            subtitle: 'Code demandé pour les menus et réglages sensibles',
            onTap: () => PinCodeDialog.changePin(context),
          ),
          const InfoBanner('Le code (4 chiffres) est propre à cet appareil. Notez-le : il est demandé pour les rubriques '
              'marquées d\'un cadenas et pour les menus protégés.'),
        ],
      );
}

// ---------------------------------------------------------------------------
// Licence & appareil
// ---------------------------------------------------------------------------

class LicencePage extends StatefulWidget {
  final Future<Map<String, Object?>> Function() hardwareInfo;
  const LicencePage({super.key, required this.hardwareInfo});

  @override
  State<LicencePage> createState() => _LicencePageState();
}

class _LicencePageState extends State<LicencePage> {
  Map<String, Object?>? _hw;
  bool _hwFailed = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    widget.hardwareInfo().then((m) {
      if (mounted) setState(() => _hw = m);
    }).catchError((_) {
      if (mounted) setState(() => _hwFailed = true);
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    await context.read<LicenceProvider>().checkLicence();
    if (!mounted) return;
    setState(() => _checking = false);
  }

  static String _date(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? (raw.isEmpty ? '—' : raw) : DateFormat('dd/MM/yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LicenceProvider>();
    final s = context.watch<SettingsProvider>();
    final lic = l.licence;
    final days = l.remainingDays;
    final (badge, fg, bg) = switch (l.status) {
      LicenceStatus.valid => (
          '$days jour${days > 1 ? 's' : ''}',
          days < 7 ? const Color(0xFF991B1B) : (days < 30 ? const Color(0xFF9A3412) : const Color(0xFF166534)),
          days < 7 ? const Color(0xFFFDECEC) : (days < 30 ? const Color(0xFFFFF4E0) : const Color(0xFFE6F4EA)),
        ),
      LicenceStatus.expired => ('Expirée', const Color(0xFF991B1B), const Color(0xFFFDECEC)),
      LicenceStatus.none => ('Absente', const Color(0xFF991B1B), const Color(0xFFFDECEC)),
      LicenceStatus.error => ('Non vérifiée', const Color(0xFF9A3412), const Color(0xFFFFF4E0)),
      LicenceStatus.loading => ('…', Pal.muted, const Color(0xFFE6EBF2)),
    };
    final hw = _hw;
    String hwText;
    if (_hwFailed) {
      hwText = 'Informations de l\'appareil indisponibles.';
    } else if (hw == null) {
      hwText = 'Lecture…';
    } else {
      final model = '${hw['manufacturer'] ?? ''} ${hw['model'] ?? ''}'.trim();
      final android = '${hw['android'] ?? ''}';
      hwText = [
        model.isEmpty ? 'Modèle : —' : 'Modèle : $model',
        if (android.isNotEmpty) 'Android $android${hw['sdk'] != null ? ' (API ${hw['sdk']})' : ''}',
        if ('${hw['device'] ?? ''}'.isNotEmpty) 'Appareil : ${hw['device']}',
      ].join('\n');
    }
    return RubriquePage(
      title: Rubrique.licence.title,
      children: [
        SettingCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: SettingText('Licence',
                    subtitle: lic == null
                        ? ParametresSummary.licence(l)
                        : 'Expire le ${_date(lic.dateEnd)}${lic.typeLicence.isEmpty ? '' : ' · ${lic.typeLicence}'}'),
              ),
              StatusBadge(badge, fg: fg, bg: bg),
            ]),
            if (lic != null && lic.id.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Identifiant de licence : ${lic.id}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
            ],
            if (l.status == LicenceStatus.error && l.errorMessage.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(l.errorMessage, style: const TextStyle(fontSize: 12.5, color: Color(0xFF7F1D1D))),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: !s.isConfigured || _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Vérifier la licence'),
              ),
            ),
          ]),
        ),
        SettingCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SettingText('Appareil'),
            const SizedBox(height: 4),
            Text(hwText, style: const TextStyle(fontSize: 13, color: Pal.ink, height: 1.5)),
          ]),
        ),
        SettingCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SettingText('Serveur utilisé'),
            const SizedBox(height: 4),
            Text(s.baseUrl, style: const TextStyle(fontSize: 13, color: Pal.ink)),
          ]),
        ),
      ],
    );
  }
}
