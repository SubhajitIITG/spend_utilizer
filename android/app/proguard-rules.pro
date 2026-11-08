# Google ML Kit text recognition (payment screenshots).
# The app only bundles the Latin-script model. The Flutter plugin also
# references the optional Chinese, Devanagari, Japanese and Korean models,
# which aren't included, so tell R8 those classes are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
