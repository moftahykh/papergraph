# نشر PaperGraph Backend على Render — دليل خطوة بخطوة

## قبل أي شيء: نظّف الأسرار

1. تأكد أن `.env` غير متتبع: نفّذ `git ls-files | findstr /i "env"` — يجب أن يظهر `.env.example` فقط.
2. ألغِ المفتاح المسرب القديم من لوحة Semantic Scholar وأنشئ مفاتيح جديدة — ستستخدم الجديدة في Render فقط، وليس في المستودع.
3. ادفع أحدث الكود (بما فيه إصلاحات: سلسلة القنوات، التخطيط v2، التعريف الجديد، وهذان الملفان) إلى GitHub.

## إنشاء الخدمة

1. ادخل render.com وسجّل بحساب GitHub.
2. **New → Web Service → اختر مستودع المشروع.**
3. الإعدادات:
   - **Root Directory:** `backend`
   - **Runtime:** Python 3
   - **Build Command:** `pip install -r requirements.txt`
   - **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
   - **Plan:** Free
4. أضف متغيرات البيئة من تبويب Environment (القيم الموجودة في render.yaml تُملأ تلقائيًا لو استخدمت Blueprint):

| المتغير | القيمة | ملاحظة |
|---|---|---|
| `SEMANTIC_SCHOLAR_API_KEYS` | `key1,key2,key3` | الجديدة بعد الإلغاء — مفصولة بفواصل |
| `NCBI_API_KEY` | مفتاح NCBI | اختياري لكنه يرفع حد الطلبات |
| `CROSSREF_MAILTO` / `OPENALEX_MAILTO` | بريدك الجامعي | للـ polite pool |
| `SMTP_USER` / `SMTP_PASSWORD` | Gmail + App Password | لإرسال OTP |
| `RATE_LIMIT_PER_MINUTE` | `240` | مهم: الـ polling أثناء التوليد يتجاوز 60/دقيقة |

> لو استخدمت Blueprint (New → Blueprint → اختر المستودع) سيقرأ render.yaml ويملأ كل شيء تلقائيًا ويسألك فقط عن الأسرار.

## التحقق بعد النشر

1. افتح `https://<اسم-خدمتك>.onrender.com/health` → يجب أن ترى `{"status":"ok"...}`.
2. افتح `https://<اسم-خدمتك>.onrender.com/api/v1/docs` → وثائق API التفاعلية.
3. جرّب OTP: من التوثيق نفّذ `POST /api/v1/auth/send-otp` ببريدك وتأكد من وصول الرسالة (لو فشلت هنا، راجع قسم الملاحظات).

## بناء نسخة التسليم من التطبيق

```
flutter build apk --release --dart-define=PAPERGRAPH_API_URL=https://<اسم-خدمتك>.onrender.com/api/v1
```

رابط Render يعمل بـ HTTPS تلقائيًا — لا حاجة لـ usesCleartextTraffic ولا لجدار الحماية ولا لنفس الشبكة. التطبيق يعمل عند أي شخص في أي مكان.

## يوم العرض — قائمة تحقق

- [ ] قبل العرض بدقيقتين: افتح رابط `/health` من متصفح جوالك (الخطة المجانية تنام بعد 15 دقيقة خمول — هذه الخطوة توقظها، أول طلب قد يأخذ ~50 ثانية).
- [ ] ولّد جرافًا واحدًا مسبقًا للورقة التي ستعرضها (الكاش يجعل إعادتها فورية).
- [ ] جوالك مفعّل عليه التطبيق بنسخة الـ APK الأخيرة.
- [ ] (احتياط) حساب demo جاهز مسبقًا حتى لا يعتمد العرض على وصول OTP لحظيًا.

## استكشاف الأخطاء

| العَرَض | السبب | الحل |
|---|---|---|
| Deploy failed: ModuleNotFoundError X | مكتبة ناقصة | أضف `X` سطرًا جديدًا في `backend/requirements.txt` وادفع |
| أول طلب بطيء جدًا (~50 ثانية) | Cold start طبيعي للخطة المجانية | أيقظ الخدمة قبل العرض بفتح `/health` |
| OTP لا يصل | قيود SMTP على الاستضافة أو App Password خاطئة | تحقق من Logs في لوحة Render؛ استخدم حسابًا منشأ مسبقًا للعرض |
| 429 من خادمك أثناء العرض | تجاوز RATE_LIMIT | ارفع `RATE_LIMIT_PER_MINUTE` أكثر من Environment ثم Manual Deploy → Restart |
| الجراف يختفي بعد Restart | التخزين in-memory بطبيعته | متوقع في هذه المرحلة — أعد التوليد (الكاش الخارجي يسرّعها) |
