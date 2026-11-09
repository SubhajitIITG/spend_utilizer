# Google ML Kit text recognition (payment screenshots).
# The app only bundles the Latin-script model. The Flutter plugin also
# references the optional Chinese, Devanagari, Japanese and Korean models,
# which aren't included, so tell R8 those classes are intentionally absent.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit and the Flutter plugin intact: parts of them are looked up
# by name at runtime, which the release shrinker can't see. If they're
# removed, reading a screenshot fails on the phone even though it builds.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
