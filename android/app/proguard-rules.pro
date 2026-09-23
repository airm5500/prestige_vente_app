# ML Kit (google_mlkit_text_recognition) : seul l'alphabet latin est embarqué.
# Les reconnaisseurs chinois / devanagari / japonais / coréens sont optionnels
# et volontairement absents ; on indique à R8 de ne pas les exiger.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
