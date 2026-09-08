# النشر على سيرفر CloudPanel

دليل تركيب الباك إند ولوحة التحكم على سيرفر Hetzner بواجهة CloudPanel.

## المتطلبات

- موقع Python متعمول من CloudPanel (`Sites → Add Site → Create a Python Site`)
- قاعدة بيانات MySQL متعمولة من CloudPanel (`Databases → Add Database`)
- صلاحية `sudo` على السيرفر

## ١. رفع الملفات

من جهازك:

```bash
# مجلد الباك إند بس — التطبيق مش محتاج يترفع على السيرفر
rsync -avz --delete \
  --exclude '.venv' --exclude '__pycache__' --exclude '.env' \
  --exclude 'media' --exclude '*.db' \
  backend/ \
  SITE_USER@SERVER_IP:/home/SITE_USER/htdocs/YOUR_DOMAIN/
```

بدّل `SITE_USER` و `SERVER_IP` و `YOUR_DOMAIN` ببياناتك.

## ٢. التركيب

على السيرفر:

```bash
cd /home/SITE_USER/htdocs/YOUR_DOMAIN
sudo bash deploy/install.sh
```

السكربت هيسألك على:
- بيانات قاعدة بيانات MySQL (من CloudPanel → Databases)
- بريد وكلمة مرور لوحة التحكم

وهيعمل: بيئة بايثون، ملف `.env` محمي، خدمة systemd، ويتأكد إن السيرفر بيرد.

> السكربت **مش بيخزّن** كلمة مرور لوحة التحكم — بيخزّن هاش bcrypt بتاعها بس.

## ٣. SSL

من CloudPanel: `Sites → موقعك → SSL/TLS → Let's Encrypt → Install`.

## ٤. المفاتيح

من `https://YOUR_DOMAIN/admin` → **إعدادات التكامل**، دخّل:

| المجموعة | المفاتيح |
|---|---|
| **Firebase** | معرّف المشروع (للتحقق من تسجيل الدخول) |
| **AdMob** | App ID ووحدات البانر والإعلان البيني والمكافأة |
| **Google Play** | اسم الحزمة، معرّفات المنتجات، مفتاح حساب الخدمة |
| **الذكاء الاصطناعي** | مفتاح Claude API واسم النموذج |

المفاتيح السرّية بتتخزّن على السيرفر بس، **ومبتوصلش للتطبيق أبدًا**.

## التحديث

```bash
# ارفع الملفات الجديدة بنفس أمر rsync، بعدين:
sudo bash deploy/update.sh
```

## متابعة الخدمة

```bash
systemctl status students-helper
journalctl -u students-helper -f      # السجل المباشر
systemctl restart students-helper
```

## النسخ الاحتياطي

الحاجتين اللي لازم تتاخد لهم نسخة:

```bash
# قاعدة البيانات
mysqldump -u DB_USER -p DB_NAME | gzip > backup-$(date +%F).sql.gz

# ملفات الكتب
tar czf media-$(date +%F).tar.gz media/
```

## ملاحظات

- **رفع الملفات الكبيرة:** الحد الافتراضي 200 ميجا (`MAX_UPLOAD_MB` في `.env`).
  لو كتاب أكبر، لازم تزوّد الحد في nginx كمان من CloudPanel
  (`Sites → Settings → Nginx → client_max_body_size`).
- **خدمة ملفات الكتب:** التطبيق بيخدمها من `/media`. للأداء الأفضل خلّي
  nginx يخدمها مباشرة بإضافة `location /media/` في إعدادات الموقع.
- **قاعدة البيانات:** الجداول بتتعمل تلقائيًا أول تشغيل. لما المشروع يكبر،
  استخدم Alembic للهجرات بدل الإنشاء التلقائي.
