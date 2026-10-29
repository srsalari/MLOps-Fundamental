# تکلیف جلسه‌ی ۶

مهلت: پیش از شروع جلسه‌ی ۷. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-6
```

```bash
set -a; source .env; set +a
```

سرور MLflow باید روشن باشد (`curl -s http://localhost:5050/health` جواب `OK` بدهد).

## ۱. دو metric تازه ثبت کنید

متریک‌های `precision` و `recall` را به تابع `score` در `src/churn/evaluate.py` اضافه کنید (از `sklearn.metrics`). شرط‌ها:

- هر دو باید در `metrics.json` بنویسند و به‌صورت metric در MLflow ثبت شوند (نیازی به تغییر `log_run` نیست؛ ببینید چرا).
- با آستانه‌ی `eval.threshold` حساب شوند، مثل `f1`.
- آزمون `test_evaluate_returns_metric_keys` در `tests/test_pipeline.py` را با کلیدهای تازه به‌روز کنید.
- `ruff` و `pytest` سبز بمانند.

```bash
uv run ruff check . && uv run ruff format --check . && uv run pytest -q
```

پیش از اجرا یک بار `uv run dvc status` بزنید و ببینید کدام مرحله `changed` است.

```bash
uv run dvc repro
```

## ۲. سه run قابل‌مقایسه بسازید

پارامتری را انتخاب کنید که **در تکلیف جلسه‌ی ۵ اضافه کردید** (مثل `train.class_weight` یا `train.solver`) و اگر نداشتید `eval.threshold`. با `dvc exp run -S` دست‌کم سه مقدار مختلف از آن را اجرا کنید؛ بین آزمایش‌ها به حالت commit‌شده برگردید (دستور برگشت در راهنمای آزمایشگاه، گام ۴ است). مقدار پایه هم باید یک run داشته باشد.

```bash
make runs
```

در UI (حالت **Model training**، experiment `churn`) این سه run و run پایه را با **Compare** کنار هم ببینید.

## ۳. مدل ثبت‌شده را از MLflow بخوانید

یک اسکریپت کوچک `scripts/predict_from_mlflow.py` بنویسید که:

1. مدل بهترین run شما (بر اساس `f1`) را از MLflow بخواند. راهنما: در UI در صفحه‌ی run، بخش **Logged models**، شناسه‌ای که با `m-` شروع می‌شود؛ و تابع `mlflow.sklearn.load_model` با نشانی `models:/<شناسه>`؛
2. پنج ردیف اول `data/processed/test.csv` (بدون ستون `churn`) را به آن بدهد و احتمال‌ها را چاپ کند.

اگر اجرا بدون خطا آویزان شد، بخش عیب‌یابی راهنمای آزمایشگاه را بخوانید و علتش را در گزارش بنویسید.

## ۴. گزارش در README پروژه

بخشی به نام `MLflow` به `README.md` پروژه اضافه کنید:

| run (نام در MLflow) | مقدار پارامتر | roc_auc | f1 | precision | recall |
|---|---|---|---|---|---|
| (پایه) | | | | | |
| | | | | | |
| | | | | | |
| | | | | | |

زیر جدول در سه یا چهار جمله بنویسید: کدام run را بهتر می‌دانید و چرا (فقط به یک metric تکیه نکنید)؛ و اینکه کدام فایل‌ها برای هر run روی `s3://mlflow` ذخیره شده‌اند.

## ۵. commit و push

بهترین آزمایش را با `dvc exp apply` به پوشه‌ی کار بیاورید.

```bash
git add . && git commit -m "feat: log precision/recall and compare runs in MLflow"
```

```bash
git push -u origin feature/homework-6
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull && uv run dvc checkout
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s06
```

2. خروجی `make runs`
3. جدول بخش `MLflow` و جملات زیر آن
4. خروجی اسکریپت `predict_from_mlflow.py`
5. یک جمله: چرا بعضی اجراهای `dvc repro` یا `dvc exp run` run تازه‌ای در MLflow نساختند؟
