
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La lecture de la version se fait maintenant automatiquement par le plugin Flutter.
// Il n'y a plus besoin de script manuel en haut du fichier.

// PrestigePOS (saveur `pos`) : sa propre version, dans prestigepos-version.properties (le pubspec.yaml reste
// celui de Prestige Mobile et ses garde-fous de version Sunmi sont inchangés). Voir docs/prestigepos/README.md.
val versionPos = Properties().apply { file("prestigepos-version.properties").inputStream().use { load(it) } }
// Prestige Pointage (saveur `pointage`, demande 57) : sa propre version, dans prestigepointage-version.properties (le
// pubspec.yaml reste celui de Prestige Mobile et ses garde-fous de version Sunmi sont inchangés). Voir
// docs/prestigepointage/README.md.
val versionPointage = Properties().apply { file("prestigepointage-version.properties").inputStream().use { load(it) } }

// 4.5.0 — CLÉ D'ENVOI (Google Play). Lue, dans cet ordre, dans les variables d'environnement (CI : secrets GitHub,
// voir .github/workflows/play.yml) puis dans android/key.properties (poste du développeur ; fichier JAMAIS commité,
// ignoré par android/.gitignore) :
//   ANDROID_KEYSTORE_PATH     / storeFile      chemin du fichier .jks (relatif à android/app ou absolu)
//   ANDROID_KEYSTORE_PASSWORD / storePassword  mot de passe du fichier
//   ANDROID_KEY_ALIAS         / keyAlias       alias de la clé
//   ANDROID_KEY_PASSWORD      / keyPassword    mot de passe de la clé
// Si l'un manque (ou si le fichier n'existe pas) : signature avec la clé DEBUG, comme avant la 4.5.0 (APK des
// terminaux Sunmi construits sur le PC du pharmacien, APK de la CI), avec un avertissement dans le journal ; Google
// Play refuse un tel paquet.
val proprietesCle = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}

fun reglageCle(variable: String, propriete: String): String? =
    System.getenv(variable)?.takeIf { it.isNotBlank() } ?: proprietesCle.getProperty(propriete)?.takeIf { it.isNotBlank() }

val cheminCle = reglageCle("ANDROID_KEYSTORE_PATH", "storeFile")
val motDePasseFichierCle = reglageCle("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val aliasCle = reglageCle("ANDROID_KEY_ALIAS", "keyAlias")
val motDePasseCle = reglageCle("ANDROID_KEY_PASSWORD", "keyPassword")

// 4.5.0 — VERSION GOOGLE PLAY : propriété Gradle « playStore », passée SEULEMENT par .github/workflows/play.yml
// (flutter build appbundle --android-project-arg=playStore=true). Google Play exige targetSdk 36 (Android 16) depuis
// le 31/08/2026 ; Android 16 change, pour une application qui le cible, l'orientation et le redimensionnement sur
// grand écran, le retour prédictif, etc. (docs/android/README.md, « Android 16 et terminaux Sunmi »). Pour ne rien
// changer aux terminaux Sunmi (kiosque, borne, scanner, impression, empreinte, caméra), les builds locaux et l'APK
// de la CI gardent les valeurs de Flutter (compileSdk / targetSdk 35) ; seul le bundle Play cible 36.
val versionPlay = (findProperty("playStore") as String?)?.trim()?.toBoolean() == true


android {
    namespace = "com.dici.prestige_vente_app"
    compileSdk = if (versionPlay) 36 else flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.dici.prestige_vente_app"
        minSdk = flutter.minSdkVersion
        targetSdk = if (versionPlay) 36 else flutter.targetSdkVersion

        // Version unique : celle de pubspec.yaml (« version: 4.0.0+8 » → versionName 4.0.0, versionCode 8).
        // Aucun numéro en dur ici (vérifié par test/version_sunmi_test.dart, voir docs/VERSIONS_SUNMI.md).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val fichierCle = cheminCle?.let { file(it) }
    val cleEnvoiComplete = fichierCle != null && fichierCle.exists() &&
        motDePasseFichierCle != null && aliasCle != null && motDePasseCle != null

    signingConfigs {
        if (cleEnvoiComplete) {
            create("release") {
                storeFile = fichierCle
                storePassword = motDePasseFichierCle
                keyAlias = aliasCle
                keyPassword = motDePasseCle
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (cleEnvoiComplete) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Prestige Mobile : clé d'envoi absente ou incomplète (ANDROID_KEYSTORE_* / android/key.properties) " +
                        "— paquet release signé avec la clé DEBUG (comme avant : APK Sunmi ; refusé par Google Play)."
                )
                signingConfigs.getByName("debug")
            }
        }
    }

    // Trois applications dans le même projet Flutter (code partagé, borne comprise) :
    //  - `mobile` : Prestige Mobile — applicationId, nom, icône, permissions et version (pubspec.yaml) de
    //    defaultConfig et de src/main, INCHANGÉS. Saveur par défaut (pubspec.yaml : flutter › default-flavor),
    //    donc « flutter build apk --release » sans --flavor construit toujours Prestige Mobile.
    //  - `pos` : PrestigePOS — com.dici.prestigepos (installable à côté de Prestige Mobile), point d'entrée
    //    lib/main_pos.dart, nom, icône, activité et permissions Bluetooth / USB dans src/pos uniquement.
    //  - `pointage` : Prestige Pointage — com.dici.prestigepointage (installable à côté de Prestige Mobile), point
    //    d'entrée lib/main_pointage.dart, nom, icône et permissions dans src/pointage uniquement.
    flavorDimensions += "appli"
    productFlavors {
        create("mobile") {
            dimension = "appli"
        }
        create("pos") {
            dimension = "appli"
            applicationId = "com.dici.prestigepos"
            versionCode = versionPos.getProperty("codeVersion").trim().toInt()
            versionName = versionPos.getProperty("nomVersion").trim()
        }
        create("pointage") {
            dimension = "appli"
            applicationId = "com.dici.prestigepointage"
            versionCode = versionPointage.getProperty("codeVersion").trim().toInt()
            versionName = versionPointage.getProperty("nomVersion").trim()
        }
    }

    // MODIFICATION : Utilisation de votre script de renommage (syntaxe Kotlin)
    // Prestige Mobile garde son nom de fichier d'origine (« prestigepos-release-4.10.0.apk ») ;
    // PrestigePOS : « PrestigePOS-release-1.0.0.apk » ; Prestige Pointage : « PrestigePointage-release-1.0.0.apk ».
    applicationVariants.all {
        val variante = this
        outputs.all {
            val outputImpl = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            // Ce script ne met que le versionName (ex: 1.2.1)
            val prefixe = when (variante.flavorName) {
                "pos" -> "PrestigePOS"
                "pointage" -> "PrestigePointage"
                else -> "prestigepos"
            }
            outputImpl.outputFileName = "$prefixe-${variante.buildType.name}-${variante.versionName}.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Vos dépendances ici...
    // Service d'empreinte Sunmi (SDK SunmiFingerprintDemo, capteur Aratek A400)
    implementation(files("libs/libsunmifingeprint_v1.0.0.aar"))
}