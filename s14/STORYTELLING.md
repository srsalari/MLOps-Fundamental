<div dir="rtl">

# راهنمای Demo، storytelling و رزومه

این راهنما برای آماده کردن Demo پنج‌دقیقه‌ای و جمله‌های رزومه است. فایل Demo خودتان `DEMO.md` است (قالب آن در همین پوشه). قانون این راهنما یکی است: **فقط چیزی بنویسید و بگویید که یک دستور یا یک نمودار آن را ثابت می‌کند.**

## ۱. ساختار یک Demo خوب (مسئله، راه‌حل، دلیل)

شنونده‌ی شما مصاحبه‌گر یا هم‌تیمی است و وقت ندارد. این ترتیب را نگه دارید:

| بخش | زمان | چه می‌گویید | مدرک روی صفحه |
|---|---|---|---|
| مسئله | ۳۰ ثانیه | چه چیزی را پیش‌بینی می‌کنید و چرا ساختن آن «سرویس» لازم است، نه یک notebook | نمودار معماری `README.md` |
| بازتولید | ۴۵ ثانیه | همین نتیجه روی هر ماشین بازتولید می‌شود | `dvc dag`، `dvc metrics show` |
| مدل | ۴۵ ثانیه | مدل با یک دروازه ارتقا می‌یابد، نه با حدس | `make models` |
| سرویس | ۶۰ ثانیه | سرویس زنده است و ما آن را می‌بینیم | `curl`، داشبورد Grafana |
| خرابی | ۶۰ ثانیه | وقتی چیزی خراب شد کاربر نفهمید و ما برگرداندیم | `helm upgrade` ناموفق، `helm rollback` |
| پایان | ۶۰ ثانیه | drift، امتیاز آمادگی، قدم بعدی | گزارش drift، `readiness_check.sh` |

نکته‌ها:

- **خرابی را عمداً نشان دهید.** Demo‌ای که هیچ‌وقت خراب نمی‌شود، باور نمی‌شود. بازگشت سریع (rollback) نشان می‌دهد شما عملیات را می‌فهمید.
- قبل از Demo یک بار همه‌چیز را کامل اجرا کنید و زمان بگیرید. پنج دقیقه یعنی پنج دقیقه.
- پیش از شروع `make demo-check` را بزنید تا وسط Demo متوجه سرویس خاموش نشوید.
- یک برنامه‌ی پشتیبان داشته باشید: یک عکس از داشبورد، یا ویدئوی سه‌دقیقه‌ای (تکلیف اختیاری).
- جمله‌ی «من ... را انتخاب کردم چون ...» از جمله‌ی «ما ... را استفاده کردیم» قوی‌تر است. دلیل تصمیم‌ها را بدانید (مثلاً چرا alias به جای stage، چرا Helm، چرا `@champion` خودکار نیست).

## ۲. جمله‌های رزومه (bullet) — بدون ادعای ساختگی

رزومه انگلیسی است. هر bullet این شکل را دارد: **فعل قوی + چه ساختید + با چه ابزاری + نتیجه‌ی قابل‌سنجش**. عدد را فقط از خروجی واقعی خودتان بردارید.

قالب‌ها (جای `<...>` را از خروجی خودتان پر کنید):

- Built an end-to-end, reproducible ML service for churn prediction (DVC, MLflow, FastAPI, Docker, Kubernetes/Helm, Prometheus/Grafana), reproducing identical metrics (ROC-AUC <عدد از `dvc metrics show`>) from a clean clone.
- Implemented a model promotion gate in the MLflow registry (aliases `@challenger` and `@champion`) so that a model is released only when ROC-AUC and F1 pass thresholds stored in version control.
- Containerized the inference API (multi-stage, non-root, health checks) and added Trivy scanning to CI; <عدد آسیب‌پذیری HIGH/CRITICAL قابل‌رفع که ندارید>.
- Deployed the service on Kubernetes with a Helm chart (dev/prod values) behind a Traefik Ingress; rolled back a failed release in <زمانی که اندازه گرفتید> without user-visible downtime.
- Added monitoring (RED metrics dashboard, alert rule) and a data-drift report with Evidently; wrote a Runbook and a production-readiness checklist scored automatically (<score>/100).
- Automated CI on Gitea Actions: lint, tests, image build, vulnerability scan, and a metrics-diff comment on pull requests.

قواعد صداقت:

| بگویید | نگویید |
|---|---|
| «روی لپ‌تاپ با kind» | «production cluster» یا «میلیون‌ها درخواست» |
| «API با ۱۰ درخواست در ثانیه آزمایش شد» | «مقیاس‌پذیر» بدون اندازه‌گیری |
| «داده‌ی ساختگی (synthetic)» | «داده‌ی واقعی مشتریان» |
| «دوره‌ی آموزشی، پروژه‌ی capstone» | «در شرکت X» اگر نبوده است |

اگر از شما بپرسند «این را خودتان ساختید؟»، باید بتوانید هر خط پروژه را توضیح دهید. چیزی را که نمی‌فهمید در رزومه نگذارید.

## ۳. سؤال‌های دفاع (جواب‌ها را برای خودتان بنویسید)

مصاحبه‌گر معمولاً از این‌ها می‌پرسد:

1. چرا alias و نه stage در MLflow؟
2. اگر `dvc pull` بدون `.env` اجرا شود چه می‌شود و چرا کلیدها در Git نیستند؟
3. چرا `dvc repro` بعد از `dvc pull` چیزی اجرا نکرد؟
4. فرق liveness و readiness چیست؟ در خرابی Demo کدام نجاتتان داد؟
5. چرا `kubectl rollout undo` روی release‌ای که Helm مدیریت می‌کند خطرناک است؟
6. Trivy در CI قرمز شد؛ چه می‌کنید؟ چرا ارتقای کتابخانه بهتر از یک استثنا است؟
7. «drift» را بدون اصطلاح توضیح دهید. چرا ۳ از ۷ ستون drift، «dataset drift» نشد؟
8. اگر ترافیک ۱۰۰ برابر شود، اول کدام بخش می‌شکند؟ (جواب صادقانه: چه چیزی را اندازه نگرفته‌اید؟)
9. این مدل چه وقت باید دوباره آموزش ببیند؟ چه کسی تصمیم می‌گیرد؟
10. این پروژه را روی cloud چطور می‌برید؟ (جدول نگاشت On-Prem و Cloud در اسلایدهای جلسه)

## ۴. ویدئوی ۳ دقیقه‌ای (تکلیف اختیاری)

از همان متن `DEMO.md` ولی کوتاه‌تر: مسئله (۲۰ ثانیه)، سرویس زنده و داشبورد (۶۰ ثانیه)، خرابی و بازگشت (۶۰ ثانیه)، امتیاز آمادگی و پایان (۴۰ ثانیه). جزئیات در `HOMEWORK.md`.

</div>
