// lib/parametres/connexion_page.dart
// Réglages · Connexion au serveur : IP locale / distante, port, nom de l'application,
// test détaillé, barre Annuler / Enregistrer seulement si modifié.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestige_vente_app/parametres/parametres_logic.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/providers/licence_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Une ligne du résultat du test.
class _Check {
  final bool? ok; // null = non vérifié
  final String text;
  const _Check(this.ok, this.text);
}

class ConnexionPage extends StatefulWidget {
  final bool adminVerified;
  final void Function(BuildContext) afterSaved;
  const ConnexionPage({super.key, required this.adminVerified, required this.afterSaved});

  @override
  State<ConnexionPage> createState() => _ConnexionPageState();
}

class _ConnexionPageState extends State<ConnexionPage> {
  late final SettingsProvider _settings = context.read<SettingsProvider>();
  late final _local = TextEditingController(text: _settings.localIp);
  late final _remote = TextEditingController(text: _settings.remoteIp);
  late final _app = TextEditingController(text: _settings.appName);
  late final _port = TextEditingController(text: _settings.port);

  bool _testing = false;
  bool _saving = false;
  List<_Check>? _result;

  @override
  void initState() {
    super.initState();
    for (final c in [_local, _remote, _app, _port]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_local, _remote, _app, _port]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _localError => ParametresChecks.host(_local.text, required: true);
  String? get _remoteError => ParametresChecks.host(_remote.text, required: false);
  String? get _portError => ParametresChecks.port(_port.text);
  String? get _appError => ParametresChecks.appName(_app.text);

  bool get _dirty =>
      _local.text.trim() != _settings.localIp ||
      _remote.text.trim() != _settings.remoteIp ||
      _app.text.trim() != _settings.appName ||
      _port.text.trim() != _settings.port;

  /// Premier champ à corriger (message sous les boutons).
  String? get _firstError {
    if (_localError != null) return 'Corrigez l\'IP locale pour enregistrer';
    if (_remoteError != null) return 'Corrigez l\'IP distante pour enregistrer';
    if (_portError != null) return 'Corrigez le port pour enregistrer';
    if (_appError != null) return 'Corrigez le nom de l\'application pour enregistrer';
    return null;
  }

  void _cancel() {
    _local.text = _settings.localIp;
    _remote.text = _settings.remoteIp;
    _app.text = _settings.appName;
    _port.text = _settings.port;
    setState(() => _result = null);
  }

  Future<void> _test() async {
    if (_testing) return;
    if (_localError != null || _portError != null || _appError != null) {
      setState(() => _result = [const _Check(false, 'Corrigez les champs en rouge avant le test.')]);
      return;
    }
    final ip = _local.text.trim(), port = _port.text.trim(), app = _app.text.trim(), remote = _remote.text.trim();
    setState(() {
      _testing = true;
      _result = null;
    });
    final checks = <_Check>[];
    final watch = Stopwatch()..start();
    final ok = await _settings.ping(ip, port, app);
    watch.stop();
    if (!mounted) return;
    final reason = _settings.pingError;
    if (ok) {
      checks.add(_Check(true, 'Serveur joignable (${watch.elapsedMilliseconds} ms)'));
      checks.add(_Check(true, 'Application Prestige trouvée ("$app")'));
    } else if (reason.startsWith('Un serveur répond')) {
      checks.add(_Check(true, 'Serveur joignable ($ip:$port)'));
      checks.add(_Check(false, reason));
    } else {
      checks.add(_Check(false, reason.isEmpty ? 'Aucun serveur ne répond à $ip:$port.' : reason));
      checks.add(const _Check(null, 'Application Prestige : non vérifiée'));
    }

    // Licence : vérifiable seulement avec l'adresse enregistrée (celle qu'utilise l'application).
    final sameAsSaved = ip == _settings.localIp && port == _settings.port && app == _settings.appName && !_settings.isRemote;
    if (!ok) {
      checks.add(const _Check(null, 'Licence : non vérifiée'));
    } else if (!sameAsSaved) {
      checks.add(const _Check(null, 'Licence : vérifiée après l\'enregistrement'));
    } else {
      final licence = context.read<LicenceProvider>();
      final status = await licence.checkLicence();
      if (!mounted) return;
      checks.add(switch (status) {
        LicenceStatus.valid => _Check(true, 'Licence valide (${licence.remainingDays} jours)'),
        LicenceStatus.expired => const _Check(false, 'Licence expirée'),
        LicenceStatus.none => const _Check(false, 'Aucune licence enregistrée sur ce serveur'),
        LicenceStatus.error => _Check(false, 'Licence non vérifiée : ${licence.errorTitle.toLowerCase()}'),
        LicenceStatus.loading => const _Check(null, 'Licence : vérification en cours'),
      });
    }

    if (remote.isNotEmpty && _remoteError == null) {
      final rOk = await _settings.ping(remote, port, app);
      if (!mounted) return;
      checks.add(_Check(rOk, rOk ? 'IP distante joignable ($remote)' : 'IP distante : ${_settings.pingError}'));
    }
    setState(() {
      _testing = false;
      _result = checks;
    });
  }

  Future<void> _save() async {
    if (_saving || _firstError != null) return;
    setState(() => _saving = true);
    // Même enregistrement que la Configuration d'origine : le serveur doit répondre.
    final success = await _settings.saveSettings(
      localIp: _local.text.trim(),
      remoteIp: _remote.text.trim(),
      appName: _app.text.trim(),
      port: _port.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) {
      Constants.showSnackBar(context, 'Paramètres enregistrés avec succès.');
      widget.afterSaved(context);
    } else {
      final reason = _settings.pingError;
      Constants.showSnackBar(context, reason.isEmpty ? 'Impossible de joindre le serveur.' : reason, isError: true);
      setState(() => _result = [_Check(false, 'Non enregistré : ${reason.isEmpty ? 'serveur injoignable.' : reason}')]);
    }
  }

  Widget _field(TextEditingController c, String label, String? error,
      {required Key key, TextInputType? keyboard, List<TextInputFormatter>? formatters, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key,
        controller: c,
        keyboardType: keyboard,
        inputFormatters: formatters,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 2,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    final error = _firstError;
    final ipFormat = [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.\-]')), LengthLimitingTextInputFormatter(253)];
    return PopScope(
      canPop: !dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmer(context,
            title: 'Abandonner les modifications ?',
            message: 'Les changements de connexion ne sont pas enregistrés.',
            action: 'Abandonner',
            danger: true);
        if (leave && context.mounted) {
          _cancel();
          Navigator.of(context).pop();
        }
      },
      child: RubriquePage(
        title: Rubrique.connexion.title,
        subtitle: widget.adminVerified ? 'Code administrateur vérifié' : null,
        bottom: !dirty
            ? null
            : BottomBar(children: [
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: outlineButton,
                        onPressed: _saving ? null : _cancel,
                        child: const Text('ANNULER'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('connexion_enregistrer'),
                        style: navyButton,
                        onPressed: error != null || _saving || _testing ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const FittedBox(child: Text('ENREGISTRER')),
                      ),
                    ),
                  ),
                ]),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Le serveur est testé avant l\'enregistrement, puis l\'application redémarre.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Pal.muted)),
                  ),
              ]),
        children: [
          _field(_local, 'Adresse IP locale', _localError,
              key: const Key('ip_locale'), keyboard: const TextInputType.numberWithOptions(decimal: true), formatters: ipFormat, hint: '192.168.1.20'),
          _field(_remote, 'Adresse IP distante (optionnel)', _remoteError,
              key: const Key('ip_distante'), keyboard: const TextInputType.numberWithOptions(decimal: true), formatters: ipFormat),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 2,
              child: _field(_port, 'Port', _portError,
                  key: const Key('port'),
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)]),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: _field(_app, 'Nom de l\'application', _appError,
                  key: const Key('nom_appli'), formatters: [LengthLimitingTextInputFormatter(60)]),
            ),
          ]),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: outlineButton.copyWith(side: const WidgetStatePropertyAll(BorderSide(color: Pal.navy, width: 1.5))),
              onPressed: _testing || _saving ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.network_ping),
              label: Text(_testing ? 'TEST EN COURS…' : 'TESTER LA CONNEXION'),
            ),
          ),
          const SizedBox(height: 10),
          if (_result != null)
            SettingCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final c in _result!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                        c.ok == null ? Icons.remove_circle_outline : (c.ok! ? Icons.check_circle : Icons.cancel),
                        size: 20,
                        color: c.ok == null ? Pal.muted : (c.ok! ? Pal.green : const Color(0xFFDC2626)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.text, style: const TextStyle(fontSize: 13.5, color: Pal.ink))),
                    ]),
                  ),
              ]),
            ),
          if (_settings.isRemote)
            const InfoBanner('L\'application utilise actuellement l\'IP distante.'),
        ],
      ),
    );
  }
}
