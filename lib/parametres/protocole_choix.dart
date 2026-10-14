// lib/parametres/protocole_choix.dart
// Choix du protocole (http / https) d'une adresse de serveur (4.1.0), commun à la nouvelle interface (Réglages ›
// Connexion au serveur) et à la Configuration d'origine. http reste le défaut (réseau local) ; https pour un
// serveur joint par Internet avec un certificat reconnu (voir docs/serveur/HTTPS_SERVEUR_WINDOWS.md).
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/serveur/adresse_serveur.dart';

class ProtocoleChoix extends StatelessWidget {
  final String valeur;
  final ValueChanged<String>? onChanged;

  /// Libellé lu par l'accessibilité (« Protocole du serveur local »).
  final String libelle;
  const ProtocoleChoix({super.key, required this.valeur, required this.onChanged, required this.libelle});

  @override
  Widget build(BuildContext context) {
    final bouton = SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: AdresseServeur.http, label: Text('http'), tooltip: 'Réseau local (sans chiffrement)'),
        ButtonSegment(value: AdresseServeur.https, label: Text('https'), tooltip: 'Internet, connexion chiffrée'),
      ],
      selected: {valeur},
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(64, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
      onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
    );
    return Semantics(
      label: libelle,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(libelle, style: const TextStyle(fontSize: 13.5)),
          FittedBox(fit: BoxFit.scaleDown, child: bouton),
        ],
      ),
    );
  }
}

/// Liaison champ d'adresse + choix du protocole : « https://… » saisi (ou collé) dans le champ règle le choix et
/// disparaît du champ ; l'adresse enregistrée est composée par [AdresseServeur.composer].
class AdresseAvecProtocole {
  final TextEditingController champ;
  String protocole;
  final VoidCallback? surChangement;
  bool _enCours = false;

  AdresseAvecProtocole(String adresseEnregistree, {this.surChangement})
      : champ = TextEditingController(text: AdresseServeur.sansProtocole(adresseEnregistree)),
        protocole = AdresseServeur.protocole(adresseEnregistree) {
    champ.addListener(_extraire);
  }

  void _extraire() {
    if (_enCours) return;
    final ecrit = AdresseServeur.protocoleEcrit(champ.text);
    if (ecrit == null) return;
    _enCours = true;
    protocole = ecrit;
    final reste = AdresseServeur.sansProtocole(champ.text);
    champ.value = TextEditingValue(text: reste, selection: TextSelection.collapsed(offset: reste.length));
    _enCours = false;
    surChangement?.call();
  }

  /// Adresse à enregistrer (« 192.168.1.50 », « https://nom », « https://nom:8443 »).
  String get adresse => AdresseServeur.composer(protocole, champ.text);

  /// Valeurs enregistrées remises dans le champ et le choix.
  void remettre(String adresseEnregistree) {
    protocole = AdresseServeur.protocole(adresseEnregistree);
    champ.text = AdresseServeur.sansProtocole(adresseEnregistree);
  }

  void dispose() => champ.dispose();
}

/// Bascule compacte « http:// » / « https:// » placée au début du champ d'adresse (nouvelle interface) : un appui
/// passe à l'autre protocole. Cible de 48 dp, libellé lu par l'accessibilité.
class ProtocoleBascule extends StatelessWidget {
  final String valeur;
  final ValueChanged<String>? onChanged;
  final String libelle;
  const ProtocoleBascule({super.key, required this.valeur, required this.onChanged, required this.libelle});

  @override
  Widget build(BuildContext context) {
    final https = valeur == AdresseServeur.https;
    final autre = https ? AdresseServeur.http : AdresseServeur.https;
    return Semantics(
      button: true,
      label: '$libelle : $valeur. Appuyer pour passer en $autre',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            foregroundColor: https ? const Color(0xFF15803D) : const Color(0xFF334155),
          ),
          onPressed: onChanged == null ? null : () => onChanged!(autre),
          icon: Icon(https ? Icons.lock_outline : Icons.lock_open_outlined, size: 18),
          label: Text('$valeur://', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
