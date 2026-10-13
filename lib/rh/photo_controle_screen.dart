// lib/rh/photo_controle_screen.dart
// Écrans de la photo de contrôle au pointage par badge :
// - [ApercuPhotoControle] : aperçu de la caméra frontale, compte à rebours en grand, état (prise / sans photo) ;
// - [PhotoControleScreen] : même chose en plein écran (pointage local, après la lecture du badge) ;
// - [expliquerEtAutoriserCamera] : explication avant la demande d'autorisation Android ;
// - [PhotosPointageScreen] : consultation par l'administrateur (photos, pointages « sans photo », conservation).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/rh/photo_controle.dart';
import 'package:prestige_vente_app/rh/rh_models.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:prestige_vente_app/widgets/responsive.dart';

const _rouge = Color(0xFFB91C1C);
const _orangeTexte = Color(0xFF8A5300);

/// Texte d'information affiché aux employés (transparence) quand la photo est active.
const String textePhotoControleEmploye = 'Une photo de contrôle est prise par la caméra avant à chaque pointage par badge.';

/// Texte sous (ou à côté de) l'aperçu : compte à rebours, « prise ✓ » ou « sans photo (motif) ».
String legendePhotoControle(CapturePhotoControle c) => switch (c.etat) {
      EtatCapture.ouverture => 'Photo de contrôle : ouverture de la caméra…',
      EtatCapture.apercu => 'Regardez l\'écran : photo dans ${c.restant} s',
      EtatCapture.capture => 'Photo…',
      EtatCapture.prise => 'Photo de contrôle prise ✓',
      EtatCapture.absente => 'Pointage ${libelleSansPhoto(c.motif ?? MotifSansPhoto.erreurCamera)} : il est enregistré quand même.',
    };

class LegendePhotoControle extends StatelessWidget {
  final CapturePhotoControle capture;
  final TextAlign align;
  const LegendePhotoControle({super.key, required this.capture, this.align = TextAlign.center});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: capture,
        builder: (context, _) {
          final etat = capture.etat;
          return Text(legendePhotoControle(capture),
              key: const Key('photo_legende'),
              textAlign: align,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: etat == EtatCapture.absente ? _orangeTexte : (etat == EtatCapture.prise ? const Color(0xFF0B6B45) : Pal.ink),
              ));
        },
      );
}

/// Aperçu de la caméra frontale avec le compte à rebours ; [taille] : côté du cadre ; [legende] : texte dessous.
class ApercuPhotoControle extends StatelessWidget {
  final CapturePhotoControle capture;
  final double taille;
  final bool legende;
  const ApercuPhotoControle({super.key, required this.capture, this.taille = 180, this.legende = true});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: capture,
        builder: (context, _) {
          final s = capture.session;
          final etat = capture.etat;
          Widget fond;
          if (s != null && (etat == EtatCapture.apercu || etat == EtatCapture.capture)) {
            fond = s.apercu();
          } else {
            fond = Container(
              color: const Color(0xFFE6EBF2),
              alignment: Alignment.center,
              child: switch (etat) {
                EtatCapture.ouverture => const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3)),
                EtatCapture.prise => const Icon(Icons.check_circle, size: 56, color: Pal.green),
                EtatCapture.absente => const Icon(Icons.no_photography_outlined, size: 56, color: _orangeTexte),
                _ => const Icon(Icons.photo_camera_front, size: 56, color: Pal.navy),
              },
            );
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              key: const Key('photo_apercu'),
              width: taille,
              height: taille,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(taille / 2),
                child: Stack(fit: StackFit.expand, children: [
                  fond,
                  if (etat == EtatCapture.apercu)
                    Center(
                      child: Text('${capture.restant}',
                          key: const Key('photo_compte_rebours'),
                          style: TextStyle(
                            fontSize: (taille * 0.4).clamp(40.0, 120.0),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
                          )),
                    ),
                ]),
              ),
            ),
            if (legende) ...[
              const SizedBox(height: 8),
              LegendePhotoControle(capture: capture),
            ],
          ]);
        },
      );
}

/// Plein écran (pointage local) : « Bonjour <nom> », aperçu ~2 s, capture, puis retour avec le résultat.
class PhotoControleScreen extends StatefulWidget {
  final PhotoControle photo;
  final String nom;
  const PhotoControleScreen({super.key, required this.photo, required this.nom});

  static Future<ResultatPhoto> ouvrir(BuildContext context, PhotoControle photo, String nom) async {
    final r = await Navigator.of(context).push<ResultatPhoto>(MaterialPageRoute(builder: (_) => PhotoControleScreen(photo: photo, nom: nom)));
    return r ?? const PhotoAbsente(MotifSansPhoto.erreurCamera);
  }

  @override
  State<PhotoControleScreen> createState() => _PhotoControleScreenState();
}

class _PhotoControleScreenState extends State<PhotoControleScreen> {
  late final CapturePhotoControle _capture = widget.photo.demarrer();
  bool _ferme = false;

  @override
  void initState() {
    super.initState();
    _capture.resultat.then((r) async {
      // Résultat visible un court instant (« prise ✓ » ou « sans photo »), puis retour au pointage.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted && !_ferme) {
        _ferme = true;
        Navigator.of(context).pop(r);
      }
    });
  }

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grand = !Responsive.isCompact(context);
    final h = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Bonjour ${widget.nom}',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: grand ? 34 : 26, fontWeight: FontWeight.bold, color: Pal.ink)),
                const SizedBox(height: 16),
                ApercuPhotoControle(capture: _capture, taille: (h * 0.4).clamp(160.0, 320.0)),
                const SizedBox(height: 12),
                const Text(textePhotoControleEmploye, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Pal.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explication puis demande d'autorisation de la caméra (Android la demande à la première ouverture).
/// Renvoie null si la caméra est prête, sinon le motif.
Future<MotifSansPhoto?> expliquerEtAutoriserCamera(BuildContext context, PhotoControle photo) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('photo_explication'),
      scrollable: true,
      title: const Text('Photo de contrôle au pointage'),
      content: const Text(
        'Pour éviter qu\'un employé pointe avec le badge d\'un collègue, la caméra avant de ce terminal prend une photo '
        'à chaque pointage par badge. L\'employé voit l\'aperçu et un compte à rebours.\n\n'
        'Les photos restent sur ce terminal (stockage privé de l\'application, jamais dans la galerie), ne sont '
        'consultables que par l\'administrateur et sont effacées automatiquement après la durée de conservation.\n\n'
        'Android va maintenant demander l\'autorisation d\'utiliser l\'appareil photo : répondez « Autoriser ». '
        'Sans autorisation, les pointages restent possibles mais sont marqués « sans photo ».',
        style: TextStyle(fontSize: 14),
      ),
      actions: [
        TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Plus tard')),
        ElevatedButton(
          key: const Key('photo_autoriser'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
  if (ok != true) return MotifSansPhoto.permissionRefusee;
  final m = await photo.preparerCamera();
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(m == null
          ? 'Caméra avant prête : la photo de contrôle sera prise à chaque pointage par badge.'
          : m == MotifSansPhoto.permissionRefusee
              ? 'Autorisation refusée : les pointages seront marqués « sans photo ». Autorisez l\'appareil photo dans '
                  'Réglages Android › Applications › Prestige › Autorisations.'
              : 'Caméra avant indisponible (${m.label}) : les pointages seront marqués « sans photo ».'),
    ));
  }
  return m;
}

// ---------------------------------------------------------------------------
// Consultation par l'administrateur
// ---------------------------------------------------------------------------

String libelleEnvoi(String envoi) {
  final s = StatutPointageBadge.values.asNameMap()[envoi];
  return s == null ? (envoi.isEmpty ? 'Pointage local (non envoyé)' : envoi) : s.label;
}

class PhotosPointageScreen extends StatefulWidget {
  final RegistrePhotosPointage registre;
  final int? retentionJours;
  const PhotosPointageScreen({super.key, required this.registre, this.retentionJours});

  @override
  State<PhotosPointageScreen> createState() => _PhotosPointageScreenState();
}

class _PhotosPointageScreenState extends State<PhotosPointageScreen> {
  bool _sansPhotoSeulement = false;
  int? _retention;

  @override
  void initState() {
    super.initState();
    _retention = widget.retentionJours;
    widget.registre.charger(forcer: true);
    if (_retention == null) {
      ReglagesPointageTerminal.charger().then((r) {
        if (mounted) setState(() => _retention = r.retentionJours);
      });
    }
  }

  Future<void> _voir(PhotoPointage p) async {
    final octets = await widget.registre.image(p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('photo_detail'),
        scrollable: true,
        title: Text(p.employeNom.isEmpty ? 'Pointage' : p.employeNom),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (octets != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Image.memory(octets, fit: BoxFit.contain, gaplessPlayback: true),
            )
          else
            const Text('Photo introuvable sur ce terminal.', style: TextStyle(color: _rouge)),
          const SizedBox(height: 8),
          Text('${DateFormat('dd/MM/yyyy HH:mm').format(p.lu)} · ${p.sens} · ${p.moyen}', style: const TextStyle(fontSize: 13.5)),
          Text(libelleEnvoi(p.envoi), style: const TextStyle(fontSize: 13, color: Pal.muted)),
        ]),
        actions: [
          TextButton(style: TextButton.styleFrom(minimumSize: const Size(64, 48)), onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.registre,
        builder: (context, _) {
          final r = widget.registre;
          final tout = r.photos;
          final liste = _sansPhotoSeulement ? tout.where((p) => !p.avecPhoto).toList() : tout;
          final sans = r.anomaliesNonTraitees;
          return Scaffold(
            backgroundColor: Pal.page,
            appBar: AppBar(title: const Text('Photos de contrôle')),
            body: ContentWidth(
              child: ListView(
                key: const Key('photos_liste'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  Text(
                    'Pointages par badge de ce terminal. Photos gardées ${_retention ?? ReglagesPointageTerminal.retentionParDefaut} jours dans le '
                    'stockage privé de l\'application, puis effacées automatiquement. Prestige ne reçoit pas encore les photos.',
                    style: const TextStyle(fontSize: 13, color: Pal.muted),
                  ),
                  const SizedBox(height: 8),
                  if (sans > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('$sans pointage(s) sans photo à vérifier.',
                          key: const Key('photos_sans_compte'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _rouge)),
                    ),
                  SwitchListTile(
                    key: const Key('photos_filtre_sans'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Seulement les pointages sans photo'),
                    value: _sansPhotoSeulement,
                    onChanged: (v) => setState(() => _sansPhotoSeulement = v),
                  ),
                  if (liste.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun pointage par badge enregistré sur ce terminal.'))),
                  for (final p in liste)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SoftCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          _Vignette(registre: r, photo: p),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p.employeNom} · ${p.sens}', style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                              Text('${DateFormat('dd/MM HH:mm').format(p.lu)} · ${p.moyen}', style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                              Text(p.etat,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.avecPhoto ? const Color(0xFF0B6B45) : _rouge)),
                              Text(libelleEnvoi(p.envoi), style: const TextStyle(fontSize: 12.5, color: Pal.muted)),
                            ]),
                          ),
                          if (p.avecPhoto)
                            IconButton(key: Key('photo_voir_${p.id}'), tooltip: 'Voir la photo', onPressed: () => _voir(p), icon: const Icon(Icons.zoom_in))
                          else
                            IconButton(
                              key: Key('photo_vu_${p.id}'),
                              tooltip: p.traitee ? 'Marquer à vérifier' : 'Marquer vu',
                              onPressed: () => r.setTraitee(p.id, !p.traitee),
                              icon: Icon(p.traitee ? Icons.check_box : Icons.check_box_outline_blank),
                            ),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _Vignette extends StatefulWidget {
  final RegistrePhotosPointage registre;
  final PhotoPointage photo;
  const _Vignette({required this.registre, required this.photo});

  @override
  State<_Vignette> createState() => _VignetteState();
}

class _VignetteState extends State<_Vignette> {
  late Future<dynamic> _octets = widget.photo.avecPhoto ? widget.registre.image(widget.photo.id) : Future.value(null);

  @override
  void didUpdateWidget(covariant _Vignette old) {
    super.didUpdateWidget(old);
    if (old.photo.id != widget.photo.id) _octets = widget.photo.avecPhoto ? widget.registre.image(widget.photo.id) : Future.value(null);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: FutureBuilder<dynamic>(
            future: _octets,
            builder: (_, s) => s.data != null
                ? Image.memory(s.data, fit: BoxFit.cover, cacheWidth: 112, gaplessPlayback: true)
                : Container(
                    color: widget.photo.avecPhoto ? const Color(0xFFE6EBF2) : const Color(0xFFFDECEC),
                    child: Icon(widget.photo.avecPhoto ? Icons.photo_camera_front : Icons.no_photography_outlined,
                        color: widget.photo.avecPhoto ? Pal.navy : _rouge),
                  ),
          ),
        ),
      );
}
