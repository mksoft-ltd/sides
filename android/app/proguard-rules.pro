# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Billing (in_app_purchase_android)
-keep class com.android.billingclient.** { *; }
-keep class com.android.vending.billing.** { *; }

# Google Mobile Ads + User Messaging Platform (consent)
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.ump.** { *; }

# Google Play Core (deferred components, referenced by the Flutter embedding)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

-keepattributes *Annotation*

# WorkManager (merged in by the ads SDK) builds its Room database by reflection
# (WorkDatabase_Impl). R8 full mode stripped the constructor and the release
# build crashed at launch in androidx.startup.InitializationProvider
# (15 Oct 2026). Keep Room databases' no-arg constructors and WorkManager's impl.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.** { *; }
