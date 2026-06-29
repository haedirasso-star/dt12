# TOTV+ TV — نسخة التلفاز (مشغّل خفيف)

تطبيق Flutter مستقل لشاشات **Android TV / Smart TV / TV Box** والجوال أيضاً.
- بلا Firebase، بلا حساب — تسجيل دخول بـ **يوزر/باسوورد فقط** والهوست ثابت مسبقاً.
- تنقّل كامل بريموت التحكم (D-pad + زر OK + رجوع).
- أقسام: الرئيسية · أفلام · مسلسلات · مباشر · بحث.
- مشغّل فيديو خفيف، كاش محلي (يفتح فوراً في المرّات التالية).
- خلفيات وبوسترات احترافية للأفلام والمسلسلات والقنوات.

## الهوست
ثابت داخل `lib/api.dart`:
```dart
const String kFixedHost = 'http://max.m950.org:2052';
```
غيّره عند الحاجة.

## خطوات البناء
هذه الحزمة تحتوي `lib/` و`pubspec.yaml` و`assets/` وملف Manifest للتلفاز.
لتوليد بقية ملفات المشروع (android/ios scaffolding):

```bash
# 1) أنشئ مشروعاً فارغاً بنفس الاسم
flutter create --org com.totvplus --project-name totvplus totvplus

# 2) انسخ فوق المشروع:
cp -r lib pubspec.yaml assets totvplus/
cp android/app/src/main/AndroidManifest.xml totvplus/android/app/src/main/AndroidManifest.xml

# 3) ثبّت الحزم وابنِ
cd totvplus
flutter pub get
flutter build apk --release
```

> مهم: الـ Manifest يفعّل `usesCleartextTraffic="true"` (لأن الهوست HTTP) و`LEANBACK_LAUNCHER` (ليظهر على واجهة التلفاز).

## أزرار الريموت في المشغّل
- **OK / Enter**: تشغيل / إيقاف
- **◀ ▶**: إرجاع / تقديم 10 ثوانٍ
- **رجوع**: خروج من المشغّل

## التبعيات
video_player · dio · shared_preferences · cached_network_image · google_fonts · audioplayers · wakelock_plus
