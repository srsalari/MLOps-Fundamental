<div dir="rtl">

# تکلیف جلسه‌ی ۷

مهلت: پیش از شروع جلسه‌ی ۸. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-7
```

```bash
set -a; source .env; set +a
```

سرور MLflow باید روشن باشد (`curl -s http://localhost:5050/health` جواب `OK` بدهد).

## ۱. یک challenger از آزمایش خودتان

پارامتری را که در تکلیف جلسه‌ی ۶ با آن سه run ساختید دوباره نگاه کنید (`make runs`). بهترین run خودتان را (به نظر خودتان، نه فقط با یک metric) ثبت کنید و دروازه را اجرا کنید:

```bash
make register RUN=<شناسه>
```

```bash
make promote
```

نتیجه هرچه بود (قبول یا رد) نگه دارید. اگر رد شد، champion را دستی عوض **نکنید**.

## ۲. یک قانون دروازه را بهتر کنید

یکی از قانون‌های بخش `gate` در `params.yaml` را عوض کنید یا یک قانون تازه به تابع `gate` در `src/churn/registry.py` اضافه کنید (مثلاً قانونی برای `f1` در مقایسه با champion، یا اگر در تکلیف جلسه‌ی ۶ `precision`/`recall` را اضافه کردید، قانونی برای یکی از آن‌ها). شرط‌ها:

- برای قانون تازه یک آزمون در `tests/test_registry.py` بنویسید که یک حالت قبول و یک حالت رد را بسنجد.
- <bdi dir="rtl">`ruff` و `pytest` سبز بمانند.</bdi>

```bash
uv run ruff check . && uv run ruff format --check . && uv run pytest -q
```

در دو یا سه جمله بنویسید چرا این قانون لازم است و چه مدلی را بیرون نگه می‌دارد که قانون‌های فعلی نگه نمی‌داشتند.

## ۳. یادداشت انتشار (Release Note)

یک فایل `RELEASE_NOTES.md` در ریشه‌ی پروژه بسازید با یک بخش برای champion فعلی. دست‌کم این موارد را داشته باشد:

| مورد | از کجا پیدا کنید |
| --- | --- |
| نام و نسخه (مثل `churn` نسخه‌ی ۳) و aliasها | `make models` یا UI |
| چه چیزی نسبت به champion قبلی عوض شد (پارامترها) | tagهای نسخه، صفحه‌ی run |
| متریک‌ها و تغییرشان نسبت به champion قبلی | tagها |
| داده (md5) و commit کد | Description نسخه، tag `data_md5` |
| نتیجه‌ی دروازه و قانون‌هایی که بررسی شد | خروجی `make promote` |
| محدودیت‌های شناخته‌شده (دست‌کم یکی) | نظر خودتان |
| راه برگشت (rollback) اگر مشکلی پیش آمد | گام ۳ راهنمای آزمایشگاه |

متن کوتاه‌شده‌ی همین یادداشت را در UI در **Description** همان نسخه (دکمه‌ی **Edit**) هم بنویسید.

## ۴. commit و push

```bash
git add . && git commit -m "docs: release note and stricter evaluation gate"
```

```bash
git push -u origin feature/homework-7
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s07
```

2. خروجی `make models`
3. خروجی `make promote` بخش ۱
4. متن `RELEASE_NOTES.md` و جمله‌های بخش ۲
5. یک جمله: چرا سرویس جلسه‌ی ۸ مدل را با `models:/churn@champion` بار می‌کند و نه با شماره‌ی نسخه؟

</div>
