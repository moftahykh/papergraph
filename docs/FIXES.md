# حزمة إصلاحات PaperGraph — 11 سبتمبر 2026

> مبنية على تقرير المراجعة المحفوظ في Notion. كل تعديل مرتبط ببند من التقرير.

## طريقة التطبيق

1. فك الضغط فوق **جذر المشروع** (المسارات مطابقة: `backend/` و `flutter_app/`) ووافق على الاستبدال.
2. احذف الملف `flutter_app/lib/providers/theme_provider.dart` يدويًا — لم يعد مستخدمًا من أي مكان.
3. تحقق:
   - `cd flutter_app && flutter pub get && flutter analyze && flutter test`
   - `cd backend && python -m pytest`
4. لبناء APK لبيئة إنتاج:
   `flutter build apk --dart-define=PAPERGRAPH_API_URL=https://YOUR_SERVER/api/v1`

## ما تم إصلاحه

### أخطاء حرجة 🔴

1. **زر الثيم** — `lib/views/home/home_view.dart` + `lib/views/settings/settings_view.dart` + `lib/main.dart`
   حُذف `ThemeProvider` من الاستخدام نهائيًا، والزر الآن يستدعي `ThemeCubit.toggleTheme()` مباشرة → الثيم يتغير فورًا بدون إعادة تشغيل التطبيق.

2. **اختلاق البيانات في الـ backend** — `app/workers/job_manager.py`
   - فشل resolve للورقة الأصلية → الـ job يفشل برسالة واضحة بدل ورقة وهمية "Publication {id}".
   - غياب candidates → فشل برسالة واضحة بدل 10 أوراق مختلقة "Related Work 0..9".
   - حُذفت imports أصبحت غير مستخدمة (`CanonicalPaper/Author`, `CandidateRecord`).

3. **تسميات WBC/NCC المعكوسة** — `lib/views/graph_view/connected_graph_view.dart`
   صُححت: WBC = Bibliographic Coupling، NCC = Co-Citation. وصُحح وصف المرحلة الأخيرة من "force-directed" إلى "deterministic 2D graph layout" (مطابق لما يفعله `layout.py` فعلًا).

4. **Race condition في البحث** — `lib/cubits/search/search_cubit.dart` (إعادة كتابة)
   - debounce 350ms يدمج الكتابة السريعة في طلب واحد (مطابق لوعد العقد).
   - CancelToken يلغي الطلب الأقدم عند وجود استعلام أحدث → لا نتائج قديمة تمسح الجديدة.
   - تجاهل صامت للطلبات الملغاة + تنظيف في `close()`.
   - للواجهة: مرّر `immediate: true` لتخطي الـ debounce (مثلًا عند ضغط زر بحث).

5. **Polling بلا سقف** — `lib/cubits/graph/graph_cubit.dart` (إعادة كتابة)
   - backoff تصاعدي: يبدأ 750ms ويتضاعف ×1.4 حتى سقف 3 ثوانٍ.
   - حد أقصى 4 دقائق ثم خطأ واضح للمستخدم بدل استنزاف لا نهائي.
   - إيقاف نظيف عند الحالات النهائية + تجاهل صامت عند إلغاء المستخدم (كان يعرض "Request was cancelled" كخطأ).

6. **حزمة provider غير معلنة** — `pubspec.yaml`
   أُضيفت `provider: ^6.1.2` صراحةً (كانت تعمل بالصدفة كتبعية غير مباشرة من flutter_bloc).

### جودة 🟡

7. `app/ranking/engine.py` — `List[any]` → `List[Any]` (كان يستخدم الـ builtin `any` كـ type annotation؛ يرفضه mypy).
8. `lib/core/network/api_client.dart` — دعم `--dart-define=PAPERGRAPH_API_URL=...` مع بقاء localhost و10.0.2.2 كافتراضي لبيئة التطوير.

## يحتاج قرارًا منك (لم أمسّها)

- **الهجرة الكاملة من Provider إلى Cubit** لـ Auth/Papers/Favorites — القاعدة #4 من خطتك تمنع Provider أصلًا. هذا refactor أكبر (إنشاء 3 cubits + تحديث كل الواجهات المرتبطة).
- **المصادقة الحقيقية** end-to-end: login فعلي عبر الـ backend + إرسال Bearer token من api_client. حاليًا التسجيل وهمي بالكامل (أي كلمة مرور ≥6 تنجح).
- **استمرارية الوظائف**: نقل jobs من الذاكرة إلى Redis/Postgres (معلنة في docker-compose لكن غير مستخدمة) + TTL للـ idempotency_map.
- **بيانات Home**: استبدال SamplePapersData بنتائج حقيقية من الـ API، أو إبقاؤها "معرض تجريبي" معلن بوضوح.
- **أداء الـ painter**: caching للـ TextPainter + تفادي تداخل العناوين عند كثرة العقد.

## أحتاج منك لو تبي أكمل

1. ملف `backend/main.py` (الموجود في جذر backend — لم يكن ضمن الـ zip) للتأكد أي main يُستخدم فعلًا وحذف المكرر.
2. قرارك بخصوص النقاط الخمس أعلاه — أي واحد نبدأ فيه؟
