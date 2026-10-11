// lib/borne/borne_reglages_page.dart
// Réglages › Borne (code administrateur demandé par la page des réglages) : activation sur CET
// appareil, présentation, inactivité, plafonds, utilisateur borne (mot de passe en stockage sécurisé),
// texte d'accueil, catégories (mots-clés), produits mis en avant, ticket discret.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_launcher.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';

/// Résumé affiché dans la liste des réglages.
String borneSummary(BorneConfig c) => c.actif
    ? 'Active sur cet appareil · ${c.presentation.label} · ${c.login.isEmpty ? 'utilisateur à renseigner' : c.login}'
    : 'Désactivée · libre-service client';

class BornePage extends StatefulWidget {
  /// Ouverture de la borne (tests) ; sinon BorneLauncher.ouvrir.
  final void Function(BuildContext)? ouvrir;
  const BornePage({super.key, this.ouvrir});

  @override
  State<BornePage> createState() => _BornePageState();
}

class _BornePageState extends State<BornePage> {
  late BorneConfig _c = BorneReglages.courant.value;
  late final _login = TextEditingController(text: _c.login);
  final _mdp = TextEditingController();
  late final _accueil = TextEditingController(text: _c.accueil);
  late final _categories = TextEditingController(text: _c.categories.map((e) => e.ligne).join('\n'));
  late final _vedettes = TextEditingController(text: _c.vedettes.join(', '));
  bool _mdpEnregistre = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    BorneReglages.secrets.lire().then((v) {
      if (mounted) setState(() => _mdpEnregistre = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    for (final c in [_login, _mdp, _accueil, _categories, _vedettes]) {
      c.dispose();
    }
    super.dispose();
  }

  BorneConfig _lu() => _c.copyWith(
        login: _login.text.trim(),
        accueil: _accueil.text,
        categories: [for (final l in _categories.text.split('\n')) BorneCategorie.parse(l)].whereType<BorneCategorie>().toList(),
        vedettes: _vedettes.text.split(RegExp(r'[\s,;]+')).where((e) => e.isNotEmpty).toList(),
      );

  Future<bool> _enregistrer({bool silencieux = false}) async {
    final c = _lu();
    final mdp = _mdp.text;
    if (c.actif && c.login.isEmpty) {
      setState(() => _erreur = 'Renseignez l\'utilisateur Prestige de la borne avant de l\'activer.');
      return false;
    }
    if (c.actif && mdp.isEmpty && !_mdpEnregistre) {
      setState(() => _erreur = 'Renseignez le mot de passe de l\'utilisateur borne.');
      return false;
    }
    if (mdp.isNotEmpty) {
      try {
        await BorneReglages.secrets.ecrire(mdp);
        _mdpEnregistre = true;
        _mdp.clear();
      } catch (e) {
        setState(() => _erreur = 'Mot de passe non enregistré (stockage sécurisé indisponible : $e).');
        return false;
      }
    }
    await BorneReglages.enregistrer(c);
    if (!mounted) return true;
    setState(() {
      _c = BorneReglages.courant.value;
      _erreur = null;
    });
    if (!silencieux) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Réglages de la borne enregistrés.')));
    }
    return true;
  }

  Future<void> _oublierMdp() async {
    await BorneReglages.secrets.ecrire(null);
    if (mounted) setState(() => _mdpEnregistre = false);
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Pal.muted, letterSpacing: .4)),
      );

  Widget _compteur(String titre, String detail, int valeur, int min, int max, ValueChanged<int> f, {int pas = 1, String cle = ''}) => ListTile(
        title: Text(titre),
        subtitle: Text(detail),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(key: ValueKey('$cle-moins'), icon: const Icon(Icons.remove_circle_outline), onPressed: valeur > min ? () => f((valeur - pas).clamp(min, max)) : null),
          SizedBox(width: 44, child: Text('$valeur', key: ValueKey('$cle-valeur'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          IconButton(key: ValueKey('$cle-plus'), icon: const Icon(Icons.add_circle_outline), onPressed: valeur < max ? () => f((valeur + pas).clamp(min, max)) : null),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'La borne permet au client de chercher ses produits, de composer son panier et d\'imprimer un ticket de prévente '
          'à présenter à la caisse. Elle est désactivée par défaut ; activée, l\'appli s\'ouvre directement sur la borne '
          '(mode kiosque, sortie par appui long de 5 s dans le coin haut gauche + code administrateur).',
          style: TextStyle(color: Pal.muted, fontSize: 13.5),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('borne-actif'),
        title: const Text('Mode borne sur cet appareil', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_c.actif ? 'Actif : la borne s\'ouvre au démarrage de l\'appli.' : 'Désactivé (appli normale).'),
        value: _c.actif,
        onChanged: (v) => setState(() => _c = _c.copyWith(actif: v)),
      ),
      _titre('Présentation'),
      for (final p in BornePresentation.values)
        RadioListTile<BornePresentation>(
          key: ValueKey('borne-presentation-${p.name}'),
          value: p,
          groupValue: _c.presentation,
          title: Text(p.label),
          subtitle: Text(p.detail),
          onChanged: (v) => setState(() => _c = _c.copyWith(presentation: v)),
        ),
      _titre('Contrôles'),
      _compteur('Retour à l\'accueil après', '${_c.inactivite} s sans action (avertissement 10 s avant)', _c.inactivite, BorneConfig.inactiviteMin,
          BorneConfig.inactiviteMax, (v) => setState(() => _c = _c.copyWith(inactivite: v)),
          pas: 10, cle: 'borne-inactivite'),
      _compteur('Quantité maximale par produit', '1 à ${BorneConfig.maxParProduitPlafond}', _c.maxParProduit, 1, BorneConfig.maxParProduitPlafond,
          (v) => setState(() => _c = _c.copyWith(maxParProduit: v)),
          cle: 'borne-max-produit'),
      _compteur('Articles maximum dans le panier', 'Somme des quantités', _c.maxArticles, 1, BorneConfig.maxArticlesPlafond,
          (v) => setState(() => _c = _c.copyWith(maxArticles: v)),
          cle: 'borne-max-articles'),
      _titre('Utilisateur Prestige de la borne'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          TextField(
            key: const ValueKey('borne-login'),
            controller: _login,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')), LengthLimitingTextInputFormatter(40)],
            decoration: const InputDecoration(labelText: 'Login (vendeur des préventes de la borne)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('borne-mdp'),
            controller: _mdp,
            obscureText: true,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: InputDecoration(
              labelText: _mdpEnregistre ? 'Mot de passe (enregistré — laisser vide pour le garder)' : 'Mot de passe',
              border: const OutlineInputBorder(),
              suffixIcon: _mdpEnregistre ? IconButton(tooltip: 'Oublier le mot de passe', icon: const Icon(Icons.delete_outline), onPressed: _oublierMdp) : null,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Mot de passe chiffré dans le stockage sécurisé d\'Android, jamais en clair. Utilisez un compte dédié '
                'aux droits limités (préventes).', style: TextStyle(fontSize: 12, color: Pal.muted)),
          ),
        ]),
      ),
      _titre('Accueil'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          TextField(
            key: const ValueKey('borne-accueil'),
            controller: _accueil,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            decoration: const InputDecoration(labelText: 'Texte d\'accueil', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('borne-categories'),
            controller: _categories,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Catégories (une par ligne : Libellé = mot-clé)',
              helperText: 'Le mot-clé (3 lettres au moins) est cherché dans le nom des produits.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('borne-vedettes'),
            controller: _vedettes,
            decoration: const InputDecoration(
              labelText: 'Produits mis en avant (codes CIP, séparés par des virgules)',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
      ),
      _titre('Ticket'),
      SwitchListTile(
        key: const ValueKey('borne-discret'),
        title: const Text('Ticket discret'),
        subtitle: const Text('Sans le nom des produits (désactivé : les produits sont imprimés sur le ticket).'),
        value: _c.ticketDiscret,
        onChanged: (v) => setState(() => _c = _c.copyWith(ticketDiscret: v)),
      ),
      if (_erreur != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(_erreur!, key: const ValueKey('borne-reglages-erreur'), style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Wrap(alignment: WrapAlignment.start,spacing: 10, runSpacing: 10, children: [
          ElevatedButton.icon(
            key: const ValueKey('borne-enregistrer'),
            onPressed: () => _enregistrer(),
            icon: const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
          if (_c.actif)
            OutlinedButton.icon(
              key: const ValueKey('borne-ouvrir'),
              onPressed: () async {
                if (!await _enregistrer(silencieux: true) || !context.mounted) return;
                (widget.ouvrir ?? BorneLauncher.ouvrir)(context);
              },
              icon: const Icon(Icons.storefront),
              label: const Text('Ouvrir la borne maintenant'),
            ),
        ]),
      ),
    ];
    return RubriquePage(
      title: 'Borne libre-service',
      subtitle: borneSummary(_c),
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items)),
        ),
      ],
    );
  }
}
