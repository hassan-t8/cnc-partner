# Keep rules for the release build (isMinifyEnabled = true).
#
# Dart code is compiled AOT and is not touched by R8 — these rules only cover
# the Java/Kotlin layer, where the plugins below rely on reflection and would
# otherwise lose classes that are never referenced statically.

# Flutter embedding.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / FCM — message handlers are instantiated by name.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# flutter_local_notifications — scheduled notifications are restored via
# reflection after a reboot, and it serializes its payloads with Gson.
-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keepattributes Signature
-keepattributes *Annotation*

# local_auth / AndroidX biometric prompt callbacks.
-keep class androidx.biometric.** { *; }

# Keep the line numbers that show up in crash reports.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
