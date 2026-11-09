<div dir="rtl">

# توضیح کد جلسه‌ی ۱

در این جلسه چهار فایل کد و تنظیمات دارید: `make_dataset.py` (ساخت داده‌ی مصنوعی)، `train.py` (آموزش مدل پایه)، `params.yaml` (تنظیمات) و `Makefile` (دستورهای کوتاه). کامنت‌های داخل فایل‌ها انگلیسی‌اند تا ویرایشگر کد درست نشان بدهد؛ توضیح فارسی کامل اینجاست.

ارتباط با جلسه‌های دیگر: خروجی `make_dataset.py` در جلسه‌ی ۴ با DVC نسخه‌گذاری می‌شود. در جلسه‌ی ۵ همین `train.py` به سه مرحله شکسته می‌شود. تابع `build_model` تا جلسه‌ی ۸ تغییر نمی‌کند.

## فایل `scripts/make_dataset.py`

**کار فایل:** یک جدول مصنوعی از مشتریان یک شرکت اینترنت می‌سازد. ستون هدف `churn` است: ۱ یعنی مشتری رفته، ۰ یعنی مانده. داده‌ی مصنوعی سه فایده دارد: مشکل محرمانگی ندارد، با seed ثابت همه‌ی دانشجوها دقیقاً همان اعداد را می‌بینند، و می‌توانیم عمداً drift بسازیم.

**نحوه‌ی اجرا** (از ریشه‌ی پروژه):

```bash
make data
uv run python scripts/make_dataset.py --rows 8000 --seed 42 --out data/raw/churn.csv
```

**ورودی و خروجی:** ورودی فقط آرگومان‌های خط فرمان است. خروجی یک فایل CSV است (پیش‌فرض `data/raw/churn.csv`).

### تابع `make`

```python
def make(rows: int, seed: int, drift: bool = False) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
```

این تابع داده را فقط در حافظه می‌سازد و فایلی نمی‌نویسد؛ برای همین تست‌ها می‌توانند آن را سریع صدا بزنند. `rng` مولد عدد تصادفی است. با seed ثابت، همیشه همان دنباله‌ی اعداد تولید می‌شود. پس دو اجرا یا دو دانشجو داده‌ی یکسان می‌گیرند (reproducible).

```python
contract = rng.choice(["month-to-month", "one-year", "two-year"], rows, p=[0.55, 0.25, 0.20])
tenure = rng.gamma(2.0, 12.0, rows).clip(1, 72).round()
charges = rng.normal(70, 20, rows).clip(18, 120).round(2)
```

برای هر مشتری یک نوع قرارداد انتخاب می‌شود؛ `p` احتمال هر گزینه است و جمعشان ۱ می‌شود. مدت عضویت (به ماه) از توزیع gamma می‌آید، چون همیشه مثبت و کج به راست است (مشتری تازه‌وارد زیاد داریم). `clip(1, 72)` مقدار را بین ۱ و ۷۲ نگه می‌دارد و `round()` آن را صحیح می‌کند. هزینه‌ی ماهانه از توزیع نرمال با میانگین ۷۰ و انحراف ۲۰ می‌آید.

```python
if drift:  # newer, more expensive, less loyal customers
    tenure = (tenure * 0.6).clip(1, 72).round()
    charges = (charges + 15).clip(18, 140).round(2)
```

اگر `--drift` بدهیم، جمعیت مشتری‌ها عوض می‌شود: عضویت ۴۰٪ کوتاه‌تر و هزینه ۱۵ واحد بیشتر. در جلسه‌های بعد از این برای نشان دادن تغییر داده (drift) استفاده می‌کنیم.

```python
logit = (
    -1.0
    - 0.05 * df.tenure_months
    + 0.03 * (df.monthly_charges - 70)
    + 1.2 * (df.contract == "month-to-month")
    + 0.35 * df.support_calls
    + 0.4 * (df.internet_service == "fiber")
)
df["churn"] = (rng.random(rows) < 1 / (1 + np.exp(-logit))).astype(int)
```

این قلب فایل است. `logit` یک «امتیاز خام ترک» است و هر خط یک قانون کسب‌وکاری: عضویت طولانی‌تر خطر را کم می‌کند، هزینه‌ی بالاتر از ۷۰ خطر را زیاد می‌کند، و قرارداد ماهانه، تماس‌های پشتیبانی و اینترنت fiber هم خطر را بالا می‌برند. عبارت `(df.contract == "...")` یک ستون True/False است که در ضرب مثل ۱ یا ۰ رفتار می‌کند.

تابع sigmoid یعنی `1 / (1 + exp(-logit))` هر عدد را به احتمالی بین ۰ و ۱ تبدیل می‌کند. بعد یک عدد تصادفی بین ۰ و ۱ می‌اندازیم؛ اگر از احتمال کوچک‌تر بود، مشتری رفته است. `astype(int)` مقدار True/False را به ۱/۰ برمی‌گرداند.

### بلوک `if __name__ == "__main__"`

```python
ap.add_argument("--drift", action="store_true")
```

این بلوک فقط وقتی اجرا می‌شود که فایل مستقیم با python اجرا شود، نه وقتی تست‌ها آن را import می‌کنند. `action="store_true"` یعنی گزینه مقدار نمی‌خواهد؛ فقط نوشتن `--drift` آن را True می‌کند. در پایان `to_csv(..., index=False)` فایل را بدون ستون شماره‌ی سطر می‌نویسد.

## فایل `src/churn/train.py`

**کار فایل:** اولین مدل پروژه را آموزش می‌دهد: Logistic Regression که احتمال ترک مشتری را پیش‌بینی می‌کند. به آن مدل پایه (baseline) می‌گوییم، یعنی ساده‌ترین مدل معقول که مدل‌های بعدی با آن مقایسه می‌شوند.

**نحوه‌ی اجرا:**

```bash
make train
```

**ورودی و خروجی:** ورودی‌ها فایل `configs/params.yaml` و داده‌ی `data/raw/churn.csv` هستند. خروجی‌ها `models/model.joblib` (کل pipeline شامل پیش‌پردازش)، `metrics.json` (دو عدد roc_auc و f1) و چاپ metrics روی صفحه هستند.

### ثابت `TARGET`

```python
TARGET = "churn"
```

نام ستون هدف یک بار اینجا تعریف می‌شود تا همه‌جا یکسان باشد. فایل‌های بعدی (تست‌ها و مرحله‌های pipeline) آن را import می‌کنند.

### تابع `build_model`

```python
num = X.select_dtypes("number").columns.tolist()
cat = [c for c in X.columns if c not in num]
pre = ColumnTransformer(
    [
        ("num", StandardScaler(), num),
        ("cat", OneHotEncoder(handle_unknown="ignore"), cat),
    ]
)
return Pipeline([("pre", pre), ("clf", LogisticRegression(C=C, max_iter=max_iter))])
```

این تابع مدل را فقط می‌سازد؛ آموزش (`fit`) بیرون از تابع انجام می‌شود. ستون‌های عددی از روی dtype پیدا می‌شوند و بقیه دسته‌ای (categorical) حساب می‌شوند. `ColumnTransformer` به هر گروه یک تبدیل جدا می‌دهد: `StandardScaler` میانگین را صفر و انحراف معیار را ۱ می‌کند، و `OneHotEncoder` هر دسته را به یک ستون ۰/۱ تبدیل می‌کند، چون مدل فقط عدد می‌فهمد.

گزینه‌ی `handle_unknown="ignore"` یعنی اگر موقع پیش‌بینی دسته‌ای دیده شود که در آموزش نبود، خطا نمی‌دهد و همه‌ی ستون‌های آن گروه را صفر می‌گذارد (تست جلسه‌ی ۲ همین را می‌سنجد).

مزیت `Pipeline` این است که پیش‌پردازش همراه مدل ذخیره می‌شود. موقع سرویس‌دهی هم دقیقاً همان تبدیل‌ها روی داده‌ی جدید اجرا می‌شوند و خطای «train/serve skew» پیش نمی‌آید. پارامتر `C` عکس قدرت regularization است: C کوچک‌تر یعنی مدل ساده‌تر و محتاط‌تر. `max_iter` حداکثر تکرار بهینه‌ساز است.

### تابع `main`

```python
X_tr, X_te, y_tr, y_te = train_test_split(
    X, y, test_size=p["data"]["test_size"], random_state=p["data"]["seed"], stratify=y
)
```

بخشی از داده را کنار می‌گذاریم (آزمون)، چون مدل هرگز نباید روی داده‌ای ارزیابی شود که با آن آموزش دیده است. `random_state` تقسیم را تکرارپذیر می‌کند. `stratify=y` نسبت ۰ و ۱ را در هر دو بخش تقریباً برابر کل داده نگه می‌دارد؛ بدون آن ممکن است تصادفاً در test مشتری «رفته» کم یا زیاد شود و عدد ارزیابی منحرف شود.

```python
model = build_model(X_tr, **p["train"]).fit(X_tr, y_tr)
proba = model.predict_proba(X_te)[:, 1]
```

علامت `**p["train"]` دیکشنری `{"C": 1.0, "max_iter": 500}` را به آرگومان‌های نام‌دار باز می‌کند. `fit` فقط روی داده‌ی آموزش صدا زده می‌شود. `predict_proba` برای هر سطر دو ستون می‌دهد (احتمال ۰ و احتمال ۱)؛ ما ستون دوم، یعنی احتمال ترک، را می‌خواهیم.

```python
"roc_auc": round(roc_auc_score(y_te, proba), 4),
"f1": round(f1_score(y_te, proba > p["eval"]["threshold"]), 4),
```

دو معیار داریم چون هر کدام چیز دیگری می‌گوید. ROC-AUC با خود احتمال‌ها کار می‌کند (بدون آستانه) و توان جدا کردن رفته از مانده را نشان می‌دهد. F1 پیش‌بینی قطعی ۰/۱ می‌خواهد، پس احتمال را با آستانه (threshold) مقایسه می‌کنیم. آستانه از `params.yaml` می‌آید.

```python
joblib.dump(model, "models/model.joblib")
pathlib.Path("metrics.json").write_text(json.dumps(metrics, indent=2))
```

کتابخانه‌ی `joblib` مدل را روی دیسک ذخیره می‌کند تا بعداً بدون آموزش دوباره لود شود. `indent=2` فایل JSON را خوانا می‌نویسد.

## فایل `configs/params.yaml`

```yaml
train:
  # inverse regularization strength: smaller C = simpler, more careful model
  C: 1.0
```

همه‌ی عددهای قابل تنظیم اینجا هستند و کد آن‌ها را می‌خواند. به این ترتیب برای امتحان یک C دیگر، پایتون را ویرایش نمی‌کنید. بخش `data` مسیر داده، `test_size` (سهم داده‌ی آزمون) و `seed` را دارد. بخش `train` شامل `C` و `max_iter` است و بخش `eval` شامل `threshold` (آستانه‌ی تبدیل احتمال به پیش‌بینی ۰/۱).

## فایل `Makefile`

```makefile
.PHONY: data train
```

نام‌های `data` و `train` نام کارند، نه نام فایل؛ `.PHONY` به make می‌گوید همیشه اجرایشان کند. هر خط دستور (recipe) باید با کاراکتر TAB شروع شود، نه space. `make data` اسکریپت ساخت داده را اجرا می‌کند و `make train` دستور `uv run python -m churn.train --config configs/params.yaml` را.

## پرسش‌هایی برای فکر کردن

- اگر `seed` را در `make` عوض کنیم، چه چیزهایی در خروجی تغییر می‌کند و چه چیزهایی نه؟
- چرا ارزیابی مدل روی همان داده‌ای که با آن آموزش دیده گمراه‌کننده است؟
- اگر `OneHotEncoder` را بدون `handle_unknown="ignore"` بنویسیم و یک نوع قرارداد جدید بیاید، چه اتفاقی می‌افتد؟

</div>
