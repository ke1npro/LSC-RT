# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# MediaPipe & JNI Hand Landmarker
-keep class com.google.mediapipe.** { *; }
-keep class io.github.iot_gamer.hand_landmarker.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Google ML Kit Face Detection
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# CameraX
-keep class androidx.camera.** { *; }

# Flutter Secure Storage & Local Auth (BiometricPrompt)
-keep class androidx.biometric.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }

# Suprimir logs de sistema en compilación Release para evitar fuga de información
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

# Ofuscación estricta de binarios
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
