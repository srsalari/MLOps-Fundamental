# تکلیف جلسه‌ی ۵

مهلت: پیش از شروع جلسه‌ی ۶. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-5
```

## ۱. یک پارامتر تازه اضافه کنید

یکی از سه گزینه را انتخاب کنید (یا پارامتر دلخواه خودتان را، با تأیید مدرس):

- **`train.class_weight`:** مقدار `balanced` یا `null` برای `LogisticRegression`. این پارامتر باید به `build_model` برسد.
- **`train.solver`:** الگوریتم بهینه‌سازی `LogisticRegression` (مثلاً `lbfgs` یا `liblinear`).
- **یک پارامتر پیش‌پردازش در بخش `data`:** مثلاً `data.drop_columns` (فهرست ستون‌هایی که از ویژگی‌ها حذف می‌شود) یا گرد کردن `monthly_charges`، در `preprocess.py`.

شرط‌ها:

- پارامتر را در `params.yaml` در **بخش درست** بگذارید. به یاد داشته باشید `build_model(**p["train"])` هر کلید زیر `train:` را به‌عنوان آرگومان می‌فرستد.
- کد را طوری عوض کنید که مقدار پیش‌فرض رفتار قبلی را حفظ کند؛ یعنی با مقدار پیش‌فرض، متریک‌ها همان `roc_auc 0.7493` و `f1 0.701` بمانند.
- ببینید `dvc.yaml` برای پارامتر شما به تغییر نیاز دارد یا نه، و دلیلش را در گزارش بنویسید. راهنما: `dvc.yaml` را بخوانید و ببینید هر مرحله دقیقاً کدام کلیدها را در `params` دارد.
- پس از تغییر `params.yaml` و پیش از `dvc repro`، یک بار `uv run dvc status` بزنید و ببینید کدام مرحله `changed` است.

```bash
uv run dvc repro
```

```bash
uv run pytest -q && uv run ruff check . && uv run ruff format --check .
```

## ۲. دست‌کم دو آزمایش اجرا کنید

با `dvc exp run -S ...` دست‌کم دو مقدار مختلف از پارامتر جدیدتان را امتحان کنید. بین آزمایش‌ها به حالت commit‌شده برگردید (دستور برگشت در راهنمای آزمایشگاه، گام ۴ است).

```bash
uv run dvc exp show --no-pager --only-changed --md --drop '^data/|^models/|^src/|Created'
```

## ۳. اثر را در README پروژه ثبت کنید

بخشی به نام `Experiments` به `README.md` پروژه اضافه کنید با یک جدول کوتاه، یک ردیف برای هر مقدار (شامل مقدار پایه) و چند جمله:

| پارامتر و مقدار | مرحله‌هایی که دوباره اجرا شدند | roc_auc | f1 |
|---|---|---|---|
| (مقدار پایه) | — | | |
| | | | |
| | | | |

زیر جدول در دو یا سه جمله بنویسید: کدام مقدار را نگه داشتید و چرا. به این فکر کنید که کدام متریک به این پارامتر حساس بود و آیا مقایسه‌ی عددها منصفانه است (داده‌ی test عوض نشده باشد).

## ۴. یک مقدار را نگه دارید، commit و push کنید

بهترین آزمایش را با `dvc exp apply` به پوشه‌ی کار بیاورید.

```bash
git add . && git commit -m "feat: add <نام پارامتر> to the pipeline"
```

```bash
uv run dvc push && git push -u origin feature/homework-5
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull && uv run dvc checkout
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s05
```

2. خروجی `uv run dvc params diff v0.3.0` و `uv run dvc metrics diff v0.3.0`
3. جدول بخش `Experiments` و جملات زیر آن
4. یک جمله: بعد از تغییر پارامترتان کدام مرحله‌ها دوباره اجرا شدند و چرا؟

## برای جلسه‌ی ۶

پروژه را سالم و روی `main` نگه دارید؛ جلسه‌ی بعد از همین پایپ‌لاین ادامه می‌دهد.
