<div dir="rtl">

# توضیح کد جلسه‌ی ۲

در این جلسه چهار فایل به پروژه اضافه می‌شود: `test_data.py` و `test_train.py` (آزمون‌های خودکار با pytest)، `pyproject-snippet.toml` (تنظیمات ruff و pytest) و `.pre-commit-config.yaml` (hookهایی که قبل از commit و push اجرا می‌شوند). کامنت‌های داخل فایل‌ها انگلیسی‌اند تا ویرایشگر کد درست نشان بدهد؛ توضیح فارسی کامل اینجاست.

ارتباط با جلسه‌های دیگر: آزمون‌ها روی کدی کار می‌کنند که در جلسه‌ی ۱ نوشتید (`make` و `build_model`). در جلسه‌ی ۵ آزمون‌های pipeline و در جلسه‌ی ۶ آزمون‌های tracking کنار این‌ها اضافه می‌شوند.

## فایل `tests/test_data.py`

**کار فایل:** دو خاصیت مهم داده را خودکار می‌سنجد: ساختار جدول (schema) درست باشد، و تولید داده تکرارپذیر باشد.

**نحوه‌ی اجرا:**

```bash
make test
```

این دستور معادل `uv run pytest -q` است. همین آزمون‌ها بعداً در pre-commit (هنگام push) و در CI هم اجرا می‌شوند. اگر کسی تابع `make` را خراب کند، قبل از ادغام کد معلوم می‌شود.

### ایمپورت `make_dataset`

```python
from make_dataset import make
```

این import کار می‌کند چون در `pyproject.toml` تنظیم `pythonpath = ["scripts"]` داریم و pytest پوشه‌ی `scripts` را به مسیر import اضافه می‌کند.

### ثابت `EXPECTED_COLUMNS`

```python
EXPECTED_COLUMNS = {
    "tenure_months",
    "monthly_charges",
    "contract",
    "internet_service",
    "payment_method",
    "support_calls",
    "churn",
}
```

مجموعه‌ی ستون‌هایی که انتظار داریم. نوع `set` ترتیب ندارد، پس ترتیب ستون‌ها مهم نیست.

### تست `test_dataset_schema`

```python
df = make(rows=200, seed=1)
assert set(df.columns) == EXPECTED_COLUMNS
assert len(df) == 200
assert set(df["churn"].unique()) <= {0, 1}
```

اگر کسی ستونی را حذف کند یا اسمش را عوض کند، مدل و سرویس‌های بعدی که این نام‌ها را انتظار دارند می‌شکنند. این تست زودتر خبر می‌دهد. علامت `<=` بین دو set یعنی «زیرمجموعه است»؛ ستون هدف فقط می‌تواند ۰ و ۱ داشته باشد.

### تست `test_dataset_is_reproducible`

```python
pd.testing.assert_frame_equal(make(200, seed=42), make(200, seed=42))
```

اگر seed یکسان باشد، داده باید دقیقاً یکسان باشد. بدون این خاصیت دو دانشجو یا دو اجرا عددهای متفاوت می‌گیرند و مقایسه‌ی مدل‌ها بی‌معنی می‌شود. تابع `assert_frame_equal` دو جدول را سلول به سلول مقایسه می‌کند و اگر تفاوتی باشد پیام دقیق می‌دهد. عملگر `==` برای DataFrame یک جدول برمی‌گرداند، نه یک True/False.

## فایل `tests/test_train.py`

**کار فایل:** مدل را آزمون می‌کند. یک تست آماده دارد و تست چهارم پروژه را (دسته‌ی ناشناخته) خودتان در آزمایشگاه می‌نویسید.

**نحوه‌ی اجرا:**

```bash
uv run pytest -q
```

### تابع کمکی `_xy`

```python
def _xy(rows=400, seed=1):
    df = make(rows, seed)
    return df.drop(columns=[TARGET]), df[TARGET]
```

یک تابع کمکی برای ساختن داده‌ی کوچک است و `(X, y)` برمی‌گرداند. pytest فقط تابع‌هایی را اجرا می‌کند که نامشان با `test_` شروع می‌شود؛ پس این تابع (با underscore اول نام) به‌عنوان تست اجرا نمی‌شود.

### تست `test_model_trains_and_predicts_probabilities`

```python
model = build_model(X, C=1.0, max_iter=200).fit(X, y)
proba = model.predict_proba(X)[:, 1]
assert len(proba) == len(X)
assert ((proba >= 0) & (proba <= 1)).all()
```

کمترین انتظار از مدل این است که بدون خطا آموزش ببیند و برای هر سطر یک احتمال بدهد. ستون دوم `predict_proba` احتمال ترک کردن است. شرط روی هر عنصر آرایه جدا بررسی می‌شود و `.all()` می‌پرسد «آیا همه True هستند؟». اگر احتمالی بیرون از بازه‌ی ۰ تا ۱ باشد، یعنی چیزی در pipeline خراب است.

### تکلیف TODO

```python
# TODO (Lab 2, step 3): write the 4th test yourself.
```

در آزمایشگاه تستی با نام `test_unseen_category_does_not_crash` می‌نویسید: مشتری‌ای با نوع قراردادی که مدل در آموزش ندیده (مثلاً `"weekly"`) نباید `predict()` را خراب کند. دلیلش `handle_unknown="ignore"` در `build_model` جلسه‌ی ۱ است.

## فایل `pyproject-snippet.toml`

**کار فایل:** این تکه را به انتهای `pyproject.toml` پروژه اضافه می‌کنید. فایل `pyproject.toml` تنظیمات مرکزی پروژه‌ی پایتون است و ابزارها (ruff و pytest) تنظیماتشان را از همین‌جا می‌خوانند.

```toml
[tool.ruff]
line-length = 100
src = ["src", "scripts", "tests"]
```

بیشترین طول هر خط ۱۰۰ کاراکتر است (قاعده‌ی E501 و `ruff format` از همین عدد استفاده می‌کنند). فهرست `src` پوشه‌هایی است که کد خودمان در آن‌هاست؛ ruff با آن می‌فهمد کدام import از پروژه‌ی ماست (first-party) و آن‌ها را جدا از کتابخانه‌های بیرونی مرتب می‌کند.

```toml
[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP"]
```

گروه قاعده‌های فعال: `E` سبک pycodestyle (مثل طول خط)، `F` خطاهای pyflakes (مثل import استفاده‌نشده)، `I` مرتب بودن importها، `B` الگوهای مشکوک flake8-bugbear و `UP` نوشتار قدیمی پایتون که باید مدرن شود.

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["scripts"]
```

ابزار pytest فقط در پوشه‌ی `tests` دنبال فایل‌های `test_*.py` می‌گردد. پوشه‌ی `scripts` به مسیر import اضافه می‌شود تا تست‌ها بتوانند `from make_dataset import make` بزنند.

## فایل `.pre-commit-config.yaml`

**کار فایل:** hookها را تعریف می‌کند؛ برنامه‌های کوچکی که pre-commit قبل از `git commit` (و برای pytest قبل از `git push`) خودکار اجرا می‌کند. اگر یکی fail شود، commit انجام نمی‌شود. معمولاً hookها از مخزن‌های اینترنتی دانلود می‌شوند؛ اینجا همه `repo: local` هستند، یعنی از ابزارهایی استفاده می‌کنند که با uv نصب کرده‌ایم و اینترنت لازم نیست.

**نحوه‌ی اجرا:** پس از نصب، با `git commit` خودکار اجرا می‌شود. برای اجرای دستی روی همه‌ی فایل‌ها این دستور را بزنید:

```bash
uv run pre-commit run --all-files
```

### بخش hook اول و دوم: ruff

```yaml
- id: ruff-check
  name: ruff (lint)
  entry: uv run ruff check --fix
  language: system
  types: [python]
```

این hook کیفیت کد را با ruff می‌سنجد. گزینه‌ی `--fix` خطاهای ساده (مثل import اضافه) را خودش درست می‌کند؛ در آن صورت commit رد می‌شود تا فایل اصلاح‌شده را دوباره `git add` کنید. مقدار `language: system` یعنی دستور را مستقیم از محیط uv اجرا کن و چیز جدا نصب نکن. مقدار `types: [python]` یعنی فقط روی فایل‌های پایتونِ stage شده اجرا شود. hook دوم (`ruff-format`) قالب کد را یکدست می‌کند.

### بخش hook سوم: ممنوعیت فایل `.env`

```yaml
- id: no-env-files
  name: block .env files
  entry: ".env files must never be committed"
  language: fail
  files: '(^|/)\.env$'
```

فایل `.env` کلیدها و رمزها را نگه می‌دارد و هرگز نباید commit شود. مقدار `language: fail` همیشه fail می‌شود و `entry` پیامی است که چاپ می‌کند. پس هر فایلی که با الگوی `files` جور باشد (هر فایلی با نام `.env`) باعث رد شدن commit می‌شود.

### بخش hook چهارم: پیدا کردن رمز در کد

```yaml
- id: no-secrets
  name: block hard-coded secrets
  language: pygrep
  types: [text]
```

مقدار `language: pygrep` یعنی `entry` یک regex پایتونی است و اگر در هر فایل متنی match شود، hook fail می‌شود. این regex دنبال نامی مثل secret، password، token یا access_key می‌گردد که بعدش `=` یا `:` و یک مقدار حداقل ۱۲ حرفی بیاید. عبارت `(?i)` یعنی بزرگی و کوچکی حروف مهم نیست. فایل `uv.lock` (هش‌های طولانی دارد) و خود این فایل از بررسی مستثنا هستند.

### بخش hook پنجم: pytest هنگام push

```yaml
- id: pytest
  name: pytest (unit tests)
  entry: uv run pytest -q
  language: system
  pass_filenames: false
  stages: [pre-push]
```

آزمون‌ها فقط در مرحله‌ی `pre-push` اجرا می‌شوند، نه در هر commit، چون کندترند. گزینه‌ی `pass_filenames: false` یعنی نام فایل‌ها به pytest داده نشود و همه‌ی تست‌ها اجرا شوند.

## پرسش‌هایی برای فکر کردن

- اگر در تابع `make` از `seed` استفاده نمی‌کردیم، کدام تست `test_data.py` گاهی یا همیشه fail می‌شد؟
- چرا hook مربوط به pytest روی `pre-push` است و نه `pre-commit`؟
- یک نمونه از متنی بنویسید که hook `no-secrets` آن را بگیرد و یک نمونه که نگیرد.

</div>
