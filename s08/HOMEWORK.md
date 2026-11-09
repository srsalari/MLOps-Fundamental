<div dir="rtl">

# تکلیف جلسه‌ی ۸

مهلت: پیش از شروع جلسه‌ی ۹. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند. بخش ۱ اختیاری است، ولی بخش‌های ۲ و ۳ لازم‌اند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-8
```

```bash
set -a; source .env; set +a
```

سرور MLflow باید روشن باشد (`curl -s http://localhost:5050/health` جواب `OK` بدهد). برای بخش ۱، اگر الگوی API را انتخاب می‌کنید، `make serve` را در ترمینال دیگر روشن نگه دارید.

## ۱. اختیاری: الگوی batch inference

<bdi dir="rtl">API برای «یک مشتری در هر درخواست» خوب است. گاهی باید یک فایل بزرگ از مشتری‌ها را یک‌جا امتیاز بدهید (مثلاً هر شب). فایل `scripts/batch_predict.py` را بنویسید که:</bdi>

- یک فایل CSV از مشتری‌ها بخواند (مثلاً `data/processed/test.csv` بدون ستون `churn`)
- برای هر ردیف احتمال churn را حساب کند
- نتیجه را در یک CSV تازه بنویسد (ستون‌های ورودی به‌علاوه‌ی `churn_probability` و `churn`)

دو راه دارید و یکی را انتخاب کنید:

| راه | معنی |
| --- | --- |
| بار کردن مدل یک‌بار | اسکریپت مثل API مدل `@champion` را یک بار بار می‌کند و همه‌ی ردیف‌ها را با هم پیش‌بینی می‌کند |
| صدا زدن API | اسکریپت برای هر ردیف (یا دسته‌ای از ردیف‌ها) به `/predict` درخواست می‌فرستد |

در سه یا چهار جمله بنویسید کدام را انتخاب کردید و چرا. به **latency** (زمان جواب یک درخواست) و **throughput** (تعداد ردیف در ثانیه) فکر کنید و بنویسید چند ردیف را در چه زمانی امتیاز دادید.

## ۲. یک آزمون از خودتان

به `tests/test_api.py` یک آزمون تازه اضافه کنید. مثال‌ها: یک مقدار مرزی که باید قبول شود و یکی درست بیرون مرز که باید `422` بگیرد (مثلاً مرز `tenure_months` یا `support_calls`)، یا یک مقدار نامعتبر برای `internet_service`. شرط‌ها:

- آزمون بدون سرور اجرا شود (مثل آزمون‌های موجود) و برای شما مفهوم باشد.
- <bdi dir="rtl">`ruff` و `pytest` سبز بمانند.</bdi>

```bash
uv run ruff check . && uv run ruff format --check . && uv run pytest -q tests/test_api.py
```

## ۳. یک پاراگراف

در یک پاراگراف کوتاه (پنج تا هشت جمله) بنویسید:

- وقتی `@champion` به نسخه‌ی تازه‌ای می‌رود، API که روشن است چه می‌کند و چه باید بشود؟
- فکر می‌کنید Kubernetes در جلسه‌ی ۱۱ (مثلاً با readiness و rollout) چطور به این مشکل کمک می‌کند؟

برای جواب خود می‌توانید آزمایش گام ۴ را دوباره ببینید، ولی متن باید از خودتان باشد.

## ۴. commit و push

```bash
git add . && git commit -m "test: extra API test and homework 8"
```

```bash
git push -u origin feature/homework-8
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull
```

## برای مدرس بفرستید

1. خروجی این دستور (API باید روشن باشد):

```bash
~/mlops-lab/scripts/verify.sh s08
```

2. نتیجه‌ی `uv run pytest -q tests/test_api.py`
3. متن آزمونی که نوشتید و یک جمله که چه چیزی را می‌سنجد
4. پاراگراف بخش ۳
5. اگر بخش ۱ را انجام دادید: فایل `scripts/batch_predict.py`، چند ردیف اول CSV خروجی، و توضیح انتخاب شما

</div>
