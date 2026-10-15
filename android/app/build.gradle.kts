
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


android {
    namespace = "com.dici.prestige_vente_app"
    compileSdk = flutter.compileSdkVersion
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
        targetSdk = flutter.targetSdkVersion

        // Version unique : celle de pubspec.yaml (« version: 4.0.0+8 » → versionName 4.0.0, versionCode 8).
        // Aucun numéro en dur ici (vérifié par test/version_sunmi_test.dart, voir docs/VERSIONS_SUNMI.md).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Deux applications dans le même projet Flutter (code partagé, borne comprise) :
    //  - `mobile` : Prestige Mobile — applicationId, nom, icône, permissions et version (pubspec.yaml) de
    //    defaultConfig et de src/main, INCHANGÉS. Saveur par défaut (pubspec.yaml : flutter › default-flavor),
    //    donc « flutter build apk --release » sans --flavor construit toujours Prestige Mobile.
    //  - `pos` : PrestigePOS — com.dici.prestigepos (installable à côté de Prestige Mobile), point d'entrée
    //    lib/main_pos.dart, nom, icône, activité et permissions Bluetooth / USB dans src/pos uniquement.
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
    }

    // MODIFICATION : Utilisation de votre script de renommage (syntaxe Kotlin)
    // Prestige Mobile garde son nom de fichier d'origine (« prestigepos-release-4.2.0.apk ») ;
    // PrestigePOS : « PrestigePOS-release-1.0.0.apk ».
    applicationVariants.all {
        val variante = this
        outputs.all {
            val outputImpl = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            // Ce script ne met que le versionName (ex: 1.2.1)
            val prefixe = if (variante.flavorName == "pos") "PrestigePOS" else "prestigepos"
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