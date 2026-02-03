
plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La lecture de la version se fait maintenant automatiquement par le plugin Flutter.
// Il n'y a plus besoin de script manuel en haut du fichier.


android {
    namespace = "com.example.prestige_vente_app"
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
        applicationId = "com.example.prestige_vente_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        // MODIFICATION : Ces lignes DOIVENT être décommentées.
        // Flutter les remplit automatiquement pendant la compilation.
        versionCode = flutter.versionCode
        versionName = "2.6.1"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // MODIFICATION : Utilisation de votre script de renommage (syntaxe Kotlin)
    applicationVariants.all {
        outputs.all {
            val outputImpl = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            // Ce script ne met que le versionName (ex: 1.2.1)
            outputImpl.outputFileName = "prestigepos-${name}-${versionName}.apk"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Vos dépendances ici...
}