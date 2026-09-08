# إعداد Firebase — الخطوات المطلوبة منك

Firebase عندنا **لتسجيل الدخول بس**. كل بيانات الطالب بتتخزّن على سيرفرك،
وFirebase بيدّي بس هوية موثوقة (توكن) السيرفر بيتحقق منها بنفسه.

الـ Bundle ID / Application ID بتاع التطبيق:

```
com.studentshelper.students_helper
```

---

## ١. اعمل المشروع

اطلع على <https://console.firebase.google.com> → **Add project**

- الاسم: `students-helper` (أو أي اسم)
- **Google Analytics: اقفلها.** التطبيق فيه مستخدمين تحت ١٣ سنة، والتحليلات
  بتعقّد الالتزام بقواعد Google Play Families من غير فايدة ليك دلوقتي.

بعد ما يتعمل، من **⚙️ Project settings → General** انسخ:

```
Project ID:  ____________________
```

الرقم ده هتحطه في `.env` على السيرفر (خطوة ٥).

---

## ٢. ضيف تطبيق أندرويد

**Project settings → Your apps → Add app → Android**

| الحقل | القيمة |
|---|---|
| Android package name | `com.studentshelper.students_helper` |
| App nickname | مساعد الطالب |
| Debug signing certificate SHA-1 | (خطوة ٣ تحت — مطلوب لتسجيل الدخول بجوجل والهاتف) |

نزّل **`google-services.json`** وابعتهولي، أو حطه بنفسك في:

```
android/app/google-services.json
```

> الملف ده **مش سري** — بيتشحن جوه أي APK وأي حد يقدر يستخرجه. الأمان
> جاي من قواعد Firebase ومن إن السيرفر بيتحقق من التوكن، مش من إخفاء الملف.

---

## ٣. بصمة SHA-1 و SHA-256

مطلوبة عشان **تسجيل الدخول بجوجل** و**التحقق برقم الموبايل** يشتغلوا.

للتجربة (debug):

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android -keypass android | grep -A2 "SHA1\|SHA256"
```

وللنشر لازم بصمة **مفتاح النشر** كمان. لو هترفع على Google Play وتستخدم
Play App Signing (وده الافتراضي)، البصمة بتاعتهم من:

**Play Console → التطبيق → Setup → App integrity → App signing key certificate**

ضيف كل البصمات في **Project settings → Your apps → Android → Add fingerprint**.

---

## ٤. فعّل طرق تسجيل الدخول

**Build → Authentication → Get started → Sign-in method**

فعّل التلاتة دول:

### أ. رقم الموبايل (Phone) — الأساسي في مصر
- **Enable**
- في **Phone numbers for testing** ضيف رقم وهمي وكود ثابت (مثلاً
  `+201000000000` والكود `123456`) — كده تقدر تجرّب من غير ما تستهلك رسائل
  ولا تستنى شبكة.
- الحصة المجانية ١٠ آلاف تحقق في الشهر. فوقها بفلوس، فخلي بالك.

### ب. البريد وكلمة السر (Email/Password)
- **Enable**
- **مفعّلش** "Email link (passwordless)" دلوقتي.

### ج. جوجل (Google)
- **Enable**
- اختار **Project support email** (بريدك).
- محتاج بصمة SHA-1 من خطوة ٣، وإلا هيفشل على الجهاز.

> **مهم:** في **Authentication → Settings → User actions** فعّل
> **Email enumeration protection** — من غيرها حد يقدر يعرف إيه الإيميلات
> المسجّلة عندك بالتجربة.

---

## ٥. اللي أنا محتاجه منك

ابعتلي:

1. **`Project ID`** (من خطوة ١)
2. **ملف `google-services.json`** (من خطوة ٢)

وأنا هحطهم في مكانهم. أو لو هتعملها بنفسك على السيرفر:

```bash
cd /home/stop4web-student-helper/htdocs/student-helper.stop4web.online
sudo nano backend/.env
# ضيف السطر ده:
FIREBASE_PROJECT_ID=المشروع-بتاعك

sudo systemctl restart students-helper
```

من غير السطر ده السيرفر هيرفض أي تسجيل دخول برسالة
`firebase_project_id غير مضبوط على السيرفر`.

---

## ٦. iOS (لما نوصله)

نفس الخطوات بس **Add app → iOS**، الـ Bundle ID نفسه، والملف اسمه
`GoogleService-Info.plist` ومكانه `ios/Runner/`.

---

## أسئلة متوقعة

**هل Firebase هيشوف بيانات ولادي؟**
لأ. بيشوف بس رقم الموبايل أو الإيميل اللي اتسجّل بيه. الجدول والدروس
والمهام والدرجات كلها على سيرفرك، وFirebase معندوش أي وصول ليها.

**هل ده بفلوس؟**
تسجيل الدخول مجاني في الباقة المجانية (Spark) ماعدا رسايل التحقق
بالموبايل: ١٠ آلاف رسالة في الشهر مجانًا، وبعد كده بتتحاسب.

**لو التوكن اتسرق؟**
بينتهي بعد ساعة، والتطبيق بيجدّده لوحده. والسيرفر بيتحقق من توقيع جوجل
على كل طلب، فمحدش يقدر يزوّر واحد.
