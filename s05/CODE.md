# توضیح کد جلسه‌ی ۵

در این جلسه کد جلسه‌ی ۱ به یک pipeline سه‌مرحله‌ای تبدیل می‌شود که DVC اجرا می‌کند. فایل‌ها: `churn/preprocess.py`، `churn/train.py`، `churn/evaluate.py`، `tests/test_pipeline.py`، `dvc.yaml`، `params.yaml` و `Makefile`. کامنت‌های داخل فایل‌ها انگلیسی‌اند تا ویرایشگر کد درست نشان بدهد؛ توضیح فارسی کامل اینجاست.

ارتباط با جلسه‌های دیگر: در جلسه‌ی ۱ همه‌ی کار داخل یک `train.py` بود. حالا سه مرحله جدا شده‌اند تا DVC هر مرحله را مستقل کش کند و فقط مرحله‌های تغییرکرده را دوباره اجرا کند. داده‌ی خام را در جلسه‌ی ۴ با DVC نسخه‌گذاری کردید. در جلسه‌ی ۶ فایل `evaluate.py` با نسخه‌ای عوض می‌شود که نتیجه را در MLflow هم ثبت می‌کند.

جریان داده: فایل `data/raw/churn.csv` به مرحله‌ی preprocess می‌رود، خروجی آن (`train.csv` و `test.csv`) به train و evaluate می‌رود، و در پایان `metrics.json` ساخته می‌شود.

## فایل `src/churn/preprocess.py`

**کار فایل:** مرحله‌ی اول. داده‌ی خام را می‌خواند و به دو بخش آموزش (train) و آزمون (test) تقسیم می‌کند.

**نحوه‌ی اجرا:**

```bash
uv run python -m churn.preprocess
```

معمولاً این مرحله را کل pipeline با `make train` اجرا می‌کند.

**ورودی و خروجی:** ورودی `params.yaml` (کلیدهای `data.raw_path`، `data.test_size`، `data.seed`) و `data/raw/churn.csv` است. خروجی `data/processed/train.csv` و `data/processed/test.csv` است.

### ثابت‌های `TARGET` و `OUT_DIR`

```python
TARGET = "churn"
OUT_DIR = pathlib.Path("data/processed")
```

نام ستون هدف و پوشه‌ی خروجی این مرحله. مرحله‌های train و evaluate هم این ثابت‌ها را از همین‌جا import می‌کنند تا فقط یک جا تعریف شده باشند. نام پوشه‌ی `data/processed` در `dvc.yaml` (بخش `outs` مرحله‌ی preprocess) هم آمده است.

### تابع `split`

```python
return train_test_split(df, test_size=test_size, random_state=seed, stratify=df[TARGET])
```

یک تقسیم تصادفی ولی تکرارپذیر. گزینه‌ی `stratify` نسبت مشتری‌های رفته و مانده را در train و test یکسان نگه می‌دارد. گزینه‌ی `random_state=seed` تقسیم را تکرارپذیر می‌کند؛ بدون آن هر اجرا فایل‌های متفاوتی می‌سازد و DVC فکر می‌کند داده عوض شده است. چون `split` جدا از `main` نوشته شده، تست‌ها می‌توانند بدون خواندن و نوشتن فایل آن را مستقیم صدا بزنند. اندیس (index) سطرهای اصلی حفظ می‌شود.

### تابع `main`

```python
OUT_DIR.mkdir(parents=True, exist_ok=True)
train.to_csv(OUT_DIR / "train.csv", index=False)
test.to_csv(OUT_DIR / "test.csv", index=False)
```

گزینه‌ی `parents=True` پوشه‌ی والد را هم در صورت نبودن می‌سازد و `exist_ok=True` اگر پوشه هست خطا نمی‌دهد. گزینه‌ی `index=False` ستون شماره‌ی سطر را در فایل نمی‌نویسد، تا ستون اضافه وارد مدل نشود. همچنین `yaml.safe_load` فایل YAML را به دیکشنری تبدیل می‌کند؛ پس `p["data"]["seed"]` یعنی کلید `seed` داخل بخش `data`.

## فایل `src/churn/train.py`

**کار فایل:** مرحله‌ی دوم. مدل رگرسیون لجستیک را فقط روی `data/processed/train.csv` آموزش می‌دهد و در `models/model.joblib` ذخیره می‌کند.

**نحوه‌ی اجرا:**

```bash
uv run python -m churn.train
```

**ورودی و خروجی:** ورودی `train.csv` (خروجی preprocess) و بخش `train` از `params.yaml` است. خروجی `models/model.joblib` است.

### تابع `build_model`

```python
return Pipeline([("pre", pre), ("clf", LogisticRegression(C=C, max_iter=max_iter))])
```

این همان تابع جلسه‌ی ۱ است، بدون تغییر. مدل یک Pipeline دوگامی است: گام اول ستون‌های عددی را استاندارد و ستون‌های متنی را one-hot می‌کند و گام دوم طبقه‌بند است. چون پیش‌پردازش داخل خود مدل است، در جلسه‌ی ۸ هم موقع پیش‌بینی همان تبدیل‌ها خودکار روی ورودی انجام می‌شوند. گزینه‌ی `handle_unknown="ignore"` باعث می‌شود دسته‌ی دیده‌نشده در آموزش خطا ندهد.

### تابع `main`

```python
model = build_model(X, **p["train"]).fit(X, y)
```

علامت `**p["train"]` دیکشنری `{"C": ..., "max_iter": ...}` را به آرگومان‌های نام‌دار باز می‌کند. همین بخش در `dvc.yaml` هم به‌عنوان `params` مرحله‌ی train آمده؛ پس تغییر `C` فقط همین مرحله و مرحله‌ی بعد را دوباره اجرا می‌کند. دقت کنید این مرحله فقط `train.csv` را می‌بیند و هیچ‌وقت test را نمی‌خواند.

## فایل `src/churn/evaluate.py`

**کار فایل:** مرحله‌ی سوم. مدل ذخیره‌شده را روی `test.csv` که مدل هرگز ندیده می‌سنجد و `metrics.json` را می‌نویسد.

**نحوه‌ی اجرا:**

```bash
uv run python -m churn.evaluate
```

**ورودی و خروجی:** ورودی `models/model.joblib`، `data/processed/test.csv` و کلید `eval.threshold` از `params.yaml` است. خروجی `metrics.json` است.

### تابع `score`

```python
proba = model.predict_proba(X)[:, 1]
return {
    "roc_auc": round(roc_auc_score(y, proba), 4),
    "f1": round(f1_score(y, proba > threshold), 4),
}
```

دو معیار می‌دهیم چون هر کدام چیز دیگری می‌گوید. `roc_auc` با خود احتمال‌ها کار می‌کند و توان جدا کردن مشتری رفته از مانده را نشان می‌دهد. `f1` پیش‌بینی قطعی ۰/۱ می‌خواهد، پس احتمال با آستانه (threshold) مقایسه می‌شود. عبارت `[:, 1]` یعنی فقط ستون دوم، یعنی احتمال کلاس ۱ (مشتری می‌رود). همین تابع در جلسه‌ی ۶ بدون تغییر در نسخه‌ی جدید `evaluate.py` می‌ماند.

### تابع `main`

```python
pathlib.Path("metrics.json").write_text(json.dumps(metrics, indent=2))
```

عدد `indent=2` فایل JSON را خوانا می‌کند و diff آن در git قابل فهم می‌شود. این فایل در `dvc.yaml` با `cache: false` تعریف شده تا مستقیم در git بماند.

## فایل `tests/test_pipeline.py`

**کار فایل:** منطق سه مرحله را بدون اجرای DVC و بدون خواندن یا نوشتن فایل می‌سنجد، فقط با داده‌ی مصنوعی کوچک در حافظه.

**نحوه‌ی اجرا:**

```bash
make test
```

### تست `test_split_sizes_and_no_overlap`

```python
train, test = split(df, test_size=0.2, seed=42)
assert len(train) == 400
assert len(test) == 100
assert set(train.index).isdisjoint(test.index)
```

اگر یک سطر هم در train و هم در test باشد (نشت داده یا data leakage)، مدل روی چیزی که قبلاً دیده امتحان می‌شود و عدد ارزیابی خوش‌بینانه و دروغ است. تابع `isdisjoint` یعنی دو مجموعه هیچ عضو مشترکی ندارند. چون `split` اندیس سطرهای اصلی را نگه می‌دارد، با مقایسه‌ی اندیس‌ها هم‌پوشانی پیدا می‌شود.

### تست `test_split_is_reproducible`

```python
a, _ = split(df, 0.2, 42)
b, _ = split(df, 0.2, 42)
assert a.index.tolist() == b.index.tolist()
```

اگر تقسیم تکرارپذیر نباشد، هر بار `dvc repro` فایل‌های متفاوت می‌سازد و نتیجه‌ها قابل مقایسه نیستند. علامت `_` یعنی بخش test را لازم نداریم.

### تست `test_evaluate_returns_metric_keys`

```python
metrics = score(model, test, threshold=0.5)
assert set(metrics) == {"roc_auc", "f1"}
assert 0 <= metrics["roc_auc"] <= 1
```

این تست کل مسیر کوچک آموزش و ارزیابی را اجرا می‌کند. اگر کسی نام کلید metric را عوض کند، `dvc metrics show` و MLflow (جلسه‌ی ۶) خراب می‌شوند؛ این تست زود نشان می‌دهد. عبارت `0 <= x <= 1` در پایتون یعنی هم `0 <= x` و هم `x <= 1`.

## فایل `dvc.yaml`

**کار فایل:** گراف مرحله‌ها را تعریف می‌کند. هر مرحله فرمان، ورودی‌ها (`deps` و `params`) و خروجی‌ها (`outs`) دارد. فرمان `dvc repro` فقط مرحله‌هایی را اجرا می‌کند که ورودی‌شان نسبت به `dvc.lock` عوض شده باشد.

```yaml
preprocess:
  cmd: uv run python -m churn.preprocess
  deps:
    - data/raw/churn.csv
    - src/churn/preprocess.py
  params:
    - data.test_size
    - data.seed
  outs:
    - data/processed
```

بخش `cmd` فرمانی است که DVC اجرا می‌کند. بخش `deps` فایل‌هایی است که اگر محتوایشان (hash) عوض شود، مرحله باید دوباره اجرا شود. بخش `params` فقط همین کلیدهای `params.yaml` را دنبال می‌کند؛ پس تغییر `C` این مرحله را اجرا نمی‌کند. بخش `outs` خروجی‌هایی است که DVC کش می‌کند و از git بیرون نگه می‌دارد (در `.gitignore` می‌آیند).

```yaml
train:
  cmd: uv run python -m churn.train
  deps:
    - data/processed/train.csv
    - src/churn/train.py
  params:
    - train
```

خروجی `train.csv` مرحله‌ی قبل، ورودی این مرحله است؛ به همین دلیل DVC ترتیب اجرا را خودش می‌فهمد. نام بخش بدون کلید (`train`) یعنی کل بخش را دنبال کن، هم `C` و هم `max_iter` را.

```yaml
metrics:
  - metrics.json:
      cache: false
```

بخش `metrics` فایل عددهای ارزیابی است که با `dvc metrics show` و `dvc metrics diff` دیده می‌شود. گزینه‌ی `cache: false` یعنی DVC آن را کش نکند و مستقیم در git بماند، چون فایل کوچک و متنی است و می‌خواهیم diff آن در git دیده شود.

## فایل `params.yaml`

```yaml
train:
  # inverse regularization strength: smaller C = simpler, more careful model
  C: 1.0
```

همه‌ی پارامترها یک‌جا هستند، با همان ساختار جلسه‌ی ۱ اما حالا در ریشه‌ی پروژه (نه در `configs/`). بخش `data` شامل مسیر داده، سهم آزمون و seed، بخش `train` شامل `C` و `max_iter`، و بخش `eval` شامل `threshold` است. DVC کلیدهای مرحله‌ها را از همین فایل می‌خواند.

## فایل `Makefile`

```makefile
train:
	uv run dvc repro
```

هدف `train` حالا به DVC سپرده شده است. فقط مرحله‌هایی که ورودی‌شان عوض شده دوباره اجرا می‌شوند و بقیه از کش می‌آیند. هدف `lint` ابتدا `ruff check` (خطاها و سبک) و بعد `ruff format --check` (یکدستی قالب) را اجرا می‌کند و هدف `test` آزمون‌ها را با pytest اجرا می‌کند. یادآوری: خط‌های دستور (recipe) باید با TAB شروع شوند.

## پرسش‌هایی برای فکر کردن

- اگر فقط `threshold` را در `params.yaml` عوض کنید، کدام مرحله‌ها دوباره اجرا می‌شوند و چرا؟
- چرا `OUT_DIR` و `TARGET` در `preprocess.py` تعریف شده‌اند و مرحله‌های دیگر آن‌ها را import می‌کنند؟
- اگر `random_state` را از `split` حذف کنیم، DVC چه رفتاری نشان می‌دهد؟
