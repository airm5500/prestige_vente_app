// lib/screens/caisse/caisse_screen.dart
// 09/11/2025 02:00 (Correction Erreur 'userFullName')
// Refonte : présentations A/B/C, actions fixées en bas, protection contre le double appui.
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/providers/caisse_provider.dart';
import 'package:prestige_vente_app/screens/product_search/product_search_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';
import 'widgets/billetage_dialog.dart';

class CaisseScreen extends StatefulWidget {
  /// Présentation imposée (tests) ; sinon celle choisie sur l'appareil (A par défaut).
  final ListPresentation? presentation;
  const CaisseScreen({super.key, this.presentation});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> with PresentationAware {
  /// Ouverture ou clôture en cours (évite le double appui).
  bool _busy = false;

  @override
  ListPresentation? get forcedPresentation => widget.presentation;

  @override
  void initState() {
    super.initState();
    loadPresentation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<CaisseProvider>(context, listen: false).loadData();
    });
  }

  void _setStyle(ListPresentation p) {
    setState(() => style = p);
    if (widget.presentation == null) PresentationPrefs.save(p);
  }

  Future<void> _reload() async {
    try {
      await Provider.of<CaisseProvider>(context, listen: false).loadData();
    } catch (_) {
      if (mounted) Constants.showSnackBar(context, 'Erreur réseau : impossible d\'actualiser la caisse.', isError: true);
    }
  }

  Future<void> _ouvrirCaisse(CaisseProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Confirmer l\'ouverture'),
          content: Text('Ouvrir la caisse pour ${orDash(provider.ouvertureData?.userFullName)} avec un fond de caisse de 0 ?'),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            ElevatedButton(
              style: navyButton,
              child: const Text('Ouvrir'),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
      if (!mounted || confirm != true) return;

      final success = await provider.ouvrirCaisse();
      if (!mounted) return;
      if (success) {
        Constants.showSnackBar(context, 'Caisse ouverte avec succès.');
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Échec de l\'ouverture de la caisse.', isError: true);
      }
    } catch (_) {
      if (mounted) Constants.showSnackBar(context, 'Erreur réseau : la caisse n\'a pas été ouverte.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cloturerCaisse(CaisseProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // 1. Recharge les dernières données de clôture
      final success = await provider.prepareCloture();
      if (!mounted) return;

      // 2. Si succès, montre la page de billetage
      if (success) {
        final clotureData = provider.clotureData;
        if (clotureData != null) {
          await Navigator.of(context).push<bool>(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => BilletageDialog(clotureData: clotureData, presentation: style),
          ));
          if (!mounted) return;
          // Après la fermeture du billetage, vérifie si l'erreur vient de là
          if (provider.errorMessage != null && provider.errorMessage!.contains("clôture")) {
            Constants.showSnackBar(context, provider.errorMessage!, isError: true);
          } else if (provider.errorMessage == null && !provider.isCaisseOuverte) {
            Constants.showSnackBar(context, 'Caisse clôturée avec succès.');
          }
        }
      } else {
        Constants.showSnackBar(context, provider.errorMessage ?? 'Erreur inconnue', isError: true);
      }
    } catch (_) {
      if (mounted) Constants.showSnackBar(context, 'Erreur réseau : la clôture n\'a pas pu être préparée.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage : A · Tableau de bord, B · Liste groupée, C · Parcours guidé
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Consumer<CaisseProvider>(
      builder: (context, provider, child) {
        final loaded = provider.ouvertureData != null;
        final bool caisseOuverte = provider.isCaisseOuverte;

        // On récupère les infos depuis le bon objet en fonction de l'état
        final String userName = orDash(caisseOuverte ? provider.clotureData?.userFullName : provider.ouvertureData?.userFullName);
        final String createAt = orDash(caisseOuverte ? provider.clotureData?.createAt : provider.ouvertureData?.createAt);
        final String dateText = caisseOuverte ? 'Ouverte le $createAt' : 'Dernière ouverture le $createAt';
        final fond = caisseOuverte ? (provider.clotureData?.cashFund ?? 0) : (provider.ouvertureData?.amount ?? 0);
        final solde = provider.clotureData?.solde;
        final showSolde = caisseOuverte && solde != null;
        final statusColor = caisseOuverte ? AppColors.success : AppColors.error;
        final statusText = caisseOuverte ? 'CAISSE OUVERTE' : 'CAISSE FERMÉE';

        return PresentationScaffold(
          style: style,
          title: 'Gestion de Caisse',
          subtitle: loaded ? userName : null,
          actions: (c) => [
            IconButton(
              tooltip: 'Actualiser',
              icon: Icon(Icons.refresh, color: c),
              onPressed: provider.isLoading || _busy ? null : _reload,
            ),
            PresentationMenuButton(value: style, onChanged: _setStyle, color: c),
          ],
          steps: StepsBar(active: caisseOuverte ? 2 : 0, steps: [
            (title: 'Ouvrir', detail: 'fond de caisse 0', onTap: null),
            (title: 'Encaisser', detail: caisseOuverte ? 'caisse en service' : 'ventes du jour', onTap: null),
            (title: 'Clôturer', detail: 'billetage', onTap: null),
          ]),
          header: [
            if (loaded)
              Row(children: [
                Expanded(child: HeaderFigure(caisseOuverte ? 'Ouverte' : 'Fermée', 'État de la caisse', highlight: caisseOuverte)),
                const SizedBox(width: 8),
                Expanded(child: HeaderFigure(Constants.formatNumber(fond), 'Fond de Caisse')),
                if (showSolde) ...[
                  const SizedBox(width: 8),
                  Expanded(child: HeaderFigure(Constants.formatNumber(solde), 'Solde théorique')),
                ],
              ]),
          ],
          compactHeader: [
            if (loaded)
              LightFigures([
                (caisseOuverte ? 'Ouverte' : 'Fermée', 'État', statusColor),
                (Constants.formatNumber(fond), 'Fond de caisse', Pal.navy),
                if (showSolde) (Constants.formatNumber(solde), 'Solde théorique', Pal.ink),
              ]),
          ],
          body: Column(children: [
            if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: _body(provider, loaded, caisseOuverte, userName, dateText, createAt, fond, showSolde ? solde : null, statusColor, statusText),
              ),
            ),
          ]),
          bottomNavigationBar: loaded ? _actions(provider, caisseOuverte) : null,
        );
      },
    );
  }

  Widget _body(CaisseProvider provider, bool loaded, bool caisseOuverte, String userName, String dateText, String createAt, int fond, int? solde,
      Color statusColor, String statusText) {
    const physics = AlwaysScrollableScrollPhysics();
    if (provider.isLoading && !loaded) {
      return ListView(physics: physics, children: const [SizedBox(height: 160), Center(child: CircularProgressIndicator())]);
    }
    if (!loaded) {
      return ListView(physics: physics, children: [
        const SizedBox(height: 60),
        InfoState(
          icon: Icons.cloud_off,
          text: 'Impossible de charger les données.\nVérifiez la connexion au serveur.',
          actionLabel: 'Réessayer',
          onAction: provider.isLoading ? null : _reload,
        ),
      ]);
    }

    final hint = caisseOuverte
        ? 'Pour clôturer, comptez les billets et pièces : l\'écart avec le solde théorique sera calculé.'
        : 'La caisse doit être ouverte pour encaisser les ventes.';

    if (style == ListPresentation.compact) {
      return ListView(physics: physics, padding: const EdgeInsets.only(top: 8, bottom: 24), children: [
        DetailLine('Utilisateur', userName, bold: true, compact: true),
        DetailLine('État', caisseOuverte ? 'Ouverte' : 'Fermée', compact: true),
        DetailLine(caisseOuverte ? 'Ouverte le' : 'Dernière ouverture', createAt, compact: true),
        DetailLine('Fond de Caisse', Constants.formatNumber(fond), compact: true),
        if (solde != null) DetailLine('Solde Théorique Actuel', Constants.formatNumber(solde), bold: true, compact: true),
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: Text(hint, style: const TextStyle(color: Pal.muted, fontSize: 13))),
      ]);
    }

    final guided = style == ListPresentation.guided;
    return ListView(physics: physics, padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      SoftCard(
        band: guided ? statusColor : null,
        child: Column(children: [
          Row(children: [
            GrossisteAvatar(userName == '—' ? '?' : userName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Utilisateur: $userName',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Pal.ink)),
                Text(dateText, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Icon(caisseOuverte ? Icons.lock_open : Icons.lock, color: statusColor, size: 64),
          const SizedBox(height: 8),
          Text(statusText, textAlign: TextAlign.center, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 6),
          Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 12),
      _infoCard('Fond de Caisse', Constants.formatNumber(fond), Icons.wallet),
      if (solde != null) ...[
        const SizedBox(height: 12),
        _infoCard('Solde Théorique Actuel', Constants.formatNumber(solde), Icons.calculate),
      ],
    ]);
  }

  Widget _infoCard(String title, String value, IconData icon) => SoftCard(
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: const Color(0xFFE3ECF7), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Pal.navy),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: Pal.muted, fontSize: 14))),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Pal.ink)),
            ),
          ),
        ]),
      );

  /// Les deux actions, fixées en bas : seule celle qui correspond à l'état est active.
  Widget _actions(CaisseProvider provider, bool caisseOuverte) {
    final locked = provider.isLoading || _busy;
    final main = style == ListPresentation.guided ? amberButton : navyButton;
    Widget button(String label, IconData icon, bool active, VoidCallback onTap) => Expanded(
          child: SizedBox(
            height: 52,
            child: active
                ? ElevatedButton.icon(
                    style: main,
                    icon: Icon(icon),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
                    onPressed: locked ? null : onTap,
                  )
                : OutlinedButton.icon(
                    style: outlineButton,
                    icon: Icon(icon),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
                    onPressed: null,
                  ),
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          // Actif seulement si la caisse est fermée
          button('Ouvrir la Caisse', Icons.lock_open, !caisseOuverte, () => _ouvrirCaisse(provider)),
          const SizedBox(width: 10),
          // Actif seulement si la caisse est ouverte
          button('Clôturer la Caisse', Icons.lock, caisseOuverte, () => _cloturerCaisse(provider)),
        ]),
      ),
    );
  }
}
