// lib/prestigepos/pos_admin.dart
// PrestigePOS — administration, ouverte après la sortie de la borne (cadenas, appui long 2 s, confirmation,
// code administrateur) : reprendre la borne, assistant, imprimante, réglages de la borne (catégories, produits
// mis en avant, plafonds, ticket discret), « Tester la borne », fermer l'application.
// Sécurité : sans action pendant 3 minutes, la borne reprend toute seule (une administration oubliée ouverte
// ne reste pas à la portée des clients).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/borne/borne_reglages_page.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_page.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/pos_app.dart';
import 'package:prestige_vente_app/prestigepos/pos_assistant.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/version_app.dart';
import 'package:prestige_vente_app/prestigepos/pos_styles.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

class PosAdminScreen extends StatefulWidget {
  /// Reprise automatique de la borne sans action (null : jamais).
  final Duration? repriseAuto;
  const PosAdminScreen({super.key, this.repriseAuto = const Duration(minutes: 3)});

  @override
  State<PosAdminScreen> createState() => _PosAdminScreenState();
}

class _PosAdminScreenState extends State<PosAdminScreen> {
  Timer? _reprise;

  @override
  void initState() {
    super.initState();
    _activite();
  }

  @override
  void dispose() {
    _reprise?.cancel();
    super.dispose();
  }

  /// Relance le délai de reprise automatique (seulement si PrestigePOS est configuré).
  void _activite() {
    _reprise?.cancel();
    final d = widget.repriseAuto;
    if (d == null) return;
    _reprise = Timer(d, () {
      if (!mounted || !PosApp.configure(context.read<SettingsProvider>())) return;
      // Seulement si l'administration est l'écran visible (pas une page ouverte par-dessus).
      if (ModalRoute.of(context)?.isCurrent ?? false) PosApp.ouvrirBorne(context);
    });
  }

  Future<void> _tester() async {
    final d = await TesteurBorne(baseUrl: context.read<ApiService>().dio.options.baseUrl).tester(BorneReglages.courant.value);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test de la borne'),
        content: SingleChildScrollView(child: DiagnosticBorneVue(d)),
        actions: [TextButton(key: const ValueKey('pos-diagnostic-fermer'), onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer'))],
      ),
    );
  }

  Future<void> _ouvrir(Widget page) async {
    _reprise?.cancel();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(_activite);
  }

  Widget _entree(String cle, IconData i, String titre, String detail, VoidCallback onTap, {bool principal = false}) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: principal ? Pal.navy : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: principal ? Pal.navy : Pal.line)),
        child: ListTile(
          key: ValueKey(cle),
          minVerticalPadding: 14,
          leading: Icon(i, color: principal ? Colors.white : Pal.navy, size: 30),
          title: Text(titre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: principal ? Colors.white : Pal.ink)),
          subtitle: Text(detail, style: TextStyle(color: principal ? Pal.headerMuted : Pal.muted)),
          trailing: Icon(Icons.chevron_right, color: principal ? Colors.white : Pal.muted),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final configure = PosApp.configure(settings);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activite(),
      child: Scaffold(
        key: const ValueKey('pos-admin'),
        backgroundColor: Pal.page,
        appBar: AppBar(
          backgroundColor: Pal.navy,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: const Text('PrestigePOS · Administration'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (configure)
                _entree('pos-admin-reprendre', Icons.storefront, 'Reprendre la borne', 'Plein écran, mode kiosque', () => PosApp.ouvrirBorne(context),
                    principal: true)
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Configuration incomplète : lancez l\'assistant.', style: TextStyle(color: Color(0xFF7C2D12))),
                ),
              _entree('pos-admin-assistant', Icons.auto_fix_high, 'Assistant de configuration', 'Serveur, utilisateur borne, présentation, imprimante',
                  () => _ouvrir(const PosAssistant())),
              _entree('pos-admin-imprimante', Icons.print, 'Imprimante de ticket', ImprimanteReglages.courant.value.resume,
                  () => _ouvrir(const PosImprimantePage())),
              _entree('pos-admin-borne', Icons.tune, 'Réglages de la borne', 'Catégories, produits mis en avant, plafonds, ticket discret',
                  () => _ouvrir(BornePage(ouvrir: (ctx) => PosApp.ouvrirBorne(ctx)))),
              _entree('pos-admin-tester', Icons.fact_check_outlined, 'Tester la borne', 'Connexion de l\'utilisateur borne et produits', _tester),
              _entree('pos-admin-fermer', Icons.power_settings_new, 'Fermer PrestigePOS', 'La borne se rouvrira au prochain lancement',
                  () => SystemNavigator.pop()),
              const SizedBox(height: 8),
              Text('${PosApp.nom} ${VersionApp.complete} · serveur ${settings.adresseAffichee(false)}',
                  textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Page « Imprimante de ticket » de l'administration.
class PosImprimantePage extends StatelessWidget {
  const PosImprimantePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('pos-imprimante-page'),
        backgroundColor: Pal.page,
        appBar: AppBar(backgroundColor: Pal.navy, foregroundColor: Colors.white, title: const Text('Imprimante de ticket')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              ImprimanteReglagesVue(officine: context.watch<AuthProvider>().officine?.nomComplet ?? ''),
            ]),
          ),
        ),
      );
}

/// Licence Prestige absente ou expirée sur le serveur : la borne ne s'ouvre pas.
class PosLicenceScreen extends StatelessWidget {
  final bool expiree;
  const PosLicenceScreen({super.key, this.expiree = false});

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('pos-licence'),
        backgroundColor: Pal.page,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_user_outlined, size: 64, color: Color(0xFF8A3A00)),
                const SizedBox(height: 12),
                Text(expiree ? 'Licence Prestige expirée' : 'Licence Prestige absente',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Pal.ink)),
                const SizedBox(height: 8),
                const Text('La borne est indisponible. Adressez-vous au comptoir.\n(Personnel : enregistrez la licence avec Prestige Mobile.)',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Pal.muted)),
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                  ElevatedButton.icon(
                    key: const ValueKey('pos-licence-reessayer'),
                    style: posBoutonBleu,
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PosDemarrage()), (_) => false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('pos-licence-admin'),
                    style: posBoutonContour,
                    onPressed: () async {
                      if (!await PosApp.codeAdmin(context) || !context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PosAdminScreen()), (_) => false);
                    },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Administration'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      );
}
