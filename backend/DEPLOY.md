# النشر على سيرفر CloudPanel

السيرفر بيسحب الكود من GitHub مباشرة — مفيش تنزيل على جهازك ولا رفع يدوي.

## المتطلبات

- موقع Python متعمول من CloudPanel (`Sites → Add Site → Create a Python Site`)
- قاعدة بيانات MySQL متعمولة من CloudPanel (`Databases → Add Database`)
- صلاحية `sudo` على السيرفر

## ١. التركيب (مرة واحدة)

ادخل السيرفر بـ SSH وشغّل:

```bash
cd /home/stop4web-student-helper/htdocs/student-helper.stop4web.online

# نجيب سكربت التركيب بس
curl -fsSLO https://raw.githubusercontent.com/ahmedmuawad/students-helper/claude/flutter-student-management-app-8bhzc6/backend/deploy/install.sh

sudo bash install.sh
```

السكربت هيعمل كل حاجة:

1. يثبّت بايثون و git وأدوات البناء
2. **يسحب المشروع من GitHub** جوّه مجلد الموقع
3. يعمل البيئة الافتراضية ويثبّت الحزم
4. يسألك على بيانات قاعدة البيانات ويتأكد من الاتصال قبل ما يكمّل
5. يسألك على بريد وكلمة مرور لوحة التحكم
6. يكتب `.env` بصلاحية `600`
7. يسجّل خدمة `systemd` ويتأكد إن السيرفر بيرد

> السكربت **مش بيخزّن** كلمة مرور لوحة التحكم — بيخزّن هاش bcrypt بتاعها بس.

### لو المستودع خاص

محتاج توفّر للسيرفر وصول قراءة. اختار واحدة:

**(أ) مفتاح نشر SSH — الأأمن (قراءة فقط)**

```bash
sudo -u stop4web-student-helper ssh-keygen -t ed25519 -N '' \
  -f /home/stop4web-student-helper/.ssh/id_ed25519
sudo cat /home/stop4web-student-helper/.ssh/id_ed25519.pub
```

ضيف المفتاح في: GitHub ← المستودع ← **Settings ← Deploy keys ← Add**
(سيبه **بدون** صلاحية الكتابة). وبعدين:

```bash
sudo REPO_URL=git@github.com:ahmedmuawad/students-helper.git bash install.sh
```

**(ب) توكن وصول شخصي** بصلاحية قراءة المحتوى فقط:

```bash
sudo REPO_URL=https://YOUR_TOKEN@github.com/ahmedmuawad/students-helper.git bash install.sh
```

## ٢. SSL

من CloudPanel: `Sites → موقعك → SSL/TLS → Let's Encrypt → Install`.

## ٣. المفاتيح

من `https://student-helper.stop4web.online/admin` ← **إعدادات التكامل**:

| المجموعة | المفاتيح |
|---|---|
| **Firebase** | معرّف المشروع (للتحقق من تسجيل الدخول) |
| **AdMob** | App ID ووحدات البانر والإعلان البيني والمكافأة |
| **Google Play** | اسم الحزمة، معرّفات المنتجات، مفتاح حساب الخدمة |
| **الذكاء الاصطناعي** | مفتاح Claude API واسم النموذج |

المفاتيح السرّية بتتخزّن على السيرفر بس **ومبتوصلش للتطبيق أبدًا**.

---

## التحديث بعد أي تعديل

أمر واحد:

```bash
sudo bash /home/stop4web-student-helper/htdocs/student-helper.stop4web.online/backend/deploy/update.sh
```

بيسحب آخر نسخة، يحدّث الحزم، يعيد تشغيل الخدمة، ويتأكد إنها ردّت.

## متابعة الخدمة

```bash
systemctl status students-helper
journalctl -u students-helper -f      # السجل المباشر
systemctl restart students-helper
```

## النسخ الاحتياطي

حاجتين لازم تتاخد لهم نسخة (الكود نفسه على GitHub فمش محتاج):

```bash
cd /home/stop4web-student-helper/htdocs/student-helper.stop4web.online

# قاعدة البيانات
mysqldump -u DB_USER -p DB_NAME | gzip > ~/backup-$(date +%F).sql.gz

# ملفات الكتب
tar czf ~/media-$(date +%F).tar.gz media/
```

> `media/` و `.env` مستثنيين من git، فـ `update.sh` مش هيمسّهم.

## ملاحظات

- **الملفات الكبيرة:** الحد 200 ميجا (`MAX_UPLOAD_MB` في `.env`). لو كتاب أكبر،
  زوّد الحد في nginx كمان من CloudPanel
  (`Sites → Settings → Nginx → client_max_body_size`).
- **خدمة ملفات الكتب:** التطبيق بيخدمها من `/media`. للأداء الأفضل خلّي nginx
  يخدمها مباشرة بإضافة `location /media/` في إعدادات الموقع.
- **قاعدة البيانات:** الجداول بتتعمل تلقائيًا أول تشغيل. لما المشروع يكبر
  استخدم Alembic للهجرات بدل الإنشاء التلقائي.
