# google_mlkit_text_recognition ships one AAR for Latin text only.
# The plugin source references optional Chinese/Devanagari/Japanese/Korean
# recogniser classes that are not on the classpath. Tell R8 to ignore them
# rather than failing the build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
