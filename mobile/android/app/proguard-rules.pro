# R8 / ProGuard rules for release builds.

# google_mlkit_text_recognition bundles only the Latin script recognizer, but
# its initializer references the optional Chinese/Devanagari/Japanese/Korean
# recognizer classes. Those aren't on the classpath, so R8 aborts with
# "Missing class ...". The app never uses those scripts — tell R8 not to warn.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# TensorFlow Lite ships optional GPU/NNAPI delegate hooks that may be absent.
-dontwarn org.tensorflow.lite.**
