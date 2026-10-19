// lib/rh/droits_rh.dart
// Qui voit quoi dans « Pointage présence » (4.4.0, décision du pharmacien) :
// - Présences du jour, Photos de contrôle et Empreintes (enrôlement) : ADMINISTRATEUR DE L'APPLICATION seulement
//   (compte « admin » de l'appli, ou profil administrateur du serveur : GET v1/roles/est-admin), c.-à-d. le pharmacien
//   ou le super administrateur. Le droit RH (P_SM_RH) seul ne les ouvre plus ;
// - Terminal de pointage : toujours ouvert aux comptes P_SM_RH ; demain aussi au droit distinct « P_RH_POINTER »
//   (demande serveur n° 52 : lecture des employés + pointage, sans la gestion RH). L'application l'accepte dès
//   aujourd'hui : GET v1/rh/droits → {success: true, pointer: true, gerer: false} ouvre le terminal ; un serveur
//   qui ne connaît que P_SM_RH répond {success: true} comme avant (repli).
// - « Mon pointage » : aucun droit RH (compte de l'application, v1/mobile ; 4.6.0 : v1/rh/moi sous la session).
// - 4.6.0 (réponse du serveur du 19/10/2026, demande 52) : GET v1/rh/droits → {success:true, pointer:true,
//   gerer:<P_SM_RH>, valider, photoRetentionJours}. Terminal ouvert avec P_RH_POINTER OU P_SM_RH ; la gestion
//   (présences, photos, empreintes) exige gerer:true ET l'administrateur de l'application. Serveur ancien (sans
//   « gerer ») : règle de la 4.4.0 (administrateur de l'application).
import 'package:flutter/widgets.dart';
import 'package:prestige_vente_app/droits/droits_modules.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:provider/provider.dart';

/// Droit distinct demandé au serveur (n° 52) : pointer au terminal sans gérer les RH.
const String droitPointerRh = 'P_RH_POINTER';

/// Droit RH complet du serveur (repli tant que [droitPointerRh] n'existe pas).
const String droitGestionRh = 'P_SM_RH';

/// Gestionnaire du pointage (présences, photos de contrôle, empreintes) : administrateur de l'application.
/// [gerer] : `gerer` de GET v1/rh/droits (null : serveur qui ne l'envoie pas → comme la 4.4.0).
bool estGestionnaireRh({required bool adminLocal, bool? adminServeur, bool? gerer}) => (adminLocal || adminServeur == true) && gerer != false;

/// Administrateur de l'application vu depuis [context] (faux sans AuthProvider : tests, écran isolé).
bool adminAppliRh(BuildContext context, {bool? gerer}) {
  var local = false;
  try {
    local = Provider.of<AuthProvider>(context, listen: false).isAdmin;
  } catch (_) {}
  return estGestionnaireRh(adminLocal: local, adminServeur: DroitsModules.instance.adminServeur, gerer: gerer);
}
