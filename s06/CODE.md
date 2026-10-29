# توضیح کد جلسه‌ی ۶

در این جلسه چهار فایل به پروژه اضافه یا جایگزین می‌شود: `churn/evaluate.py` (جای نسخه‌ی جلسه‌ی ۵)، `scripts/list_runs.py`، `tests/test_tracking.py` و `Makefile`. کامنت‌های داخل فایل‌ها انگلیسی‌اند تا ویرایشگر کد درست نشان بدهد؛ توضیح فارسی کامل اینجاست.

ارتباط با جلسه‌های دیگر: کار قبلی `evaluate` (محاسبه‌ی roc_auc و f1 و نوشتن `metrics.json`) همان است، ولی حالا هر اجرا در MLflow هم «ثبت» می‌شود: پارامترها، metricها، فایل‌ها و خود مدل. به این ثبت یک run می‌گوییم و همه‌ی runهای پروژه در یک experiment به نام `churn` جمع می‌شوند. در جلسه‌ی ۷ همین runها مبنای ثبت مدل در Registry و alias به نام `champion` هستند.

## فایل `src/churn/evaluate.py`

**کار فایل:** مرحله‌ی سوم pipeline، با اضافه شدن ثبت در MLflow.

**نحوه‌ی اجرا:**

```bash
make train
```

برای امتحان یک `C` دیگر (هر آزمایش یک run می‌سازد):

```bash
uv run dvc exp run -S train.C=0.1
```

برای تکرار آزمایشی که قبلاً اجرا شده، گزینه‌ی `-f` لازم است، وگرنه DVC از cache استفاده می‌کند:

```bash
uv run dvc exp run -f -S train.C=0.1
```

**ورودی و خروجی:** ورودی‌ها `models/model.joblib`، `data/processed/test.csv`، `params.yaml` و (اختیاری) `data/raw/churn.csv.dvc` برای خواندن md5 داده هستند. خروجی‌ها `metrics.json` و یک run روی سرور MLflow هستند. سرور باید روشن باشد (`docker compose up -d seaweedfs mlflow`). فایل‌های run را خود سرور MLflow در bucket به نام `mlflow` در SeaweedFS (S3) ذخیره می‌کند؛ کلاینت مستقیم با S3 حرف نمی‌زند.

### ثابت‌های `DEFAULT_URI` و `EXPERIMENT`

```python
DEFAULT_URI = "http://localhost:5050"
EXPERIMENT = "churn"
```

آدرس پیش‌فرض سرور MLflow روی همین لپ‌تاپ است (پورت ۵۰۵۰ در compose). نام experiment مثل یک پوشه‌ی منطقی است که همه‌ی runهای این پروژه داخلش جمع می‌شوند.

### تابع `score`

```python
proba = model.predict_proba(X)[:, 1]
return {
    "roc_auc": round(roc_auc_score(y, proba), 4),
    "f1": round(f1_score(y, proba > threshold), 4),
}
```

این تابع از جلسه‌ی ۵ تغییری نکرده است. `roc_auc` با خود احتمال‌ها محاسبه می‌شود (بدون آستانه). `f1` پیش‌بینی قطعی می‌خواهد و آن را از مقایسه‌ی احتمال با `threshold` می‌گیریم.

### تابع `flatten`

```python
for key, value in d.items():
    name = f"{prefix}{key}"
    if isinstance(value, dict):
        out.update(flatten(value, f"{name}."))
    else:
        out[name] = value
```

سرور MLflow پارامترها را فقط به شکل «نام: مقدار» (تخت) می‌پذیرد، ولی `params.yaml` تو در تو است (بخش `train` شامل `C` و `max_iter`). این تابع بخش‌های تو در تو را با نقطه به هم می‌چسباند، مثلاً `{'train': {'C': 0.1}}` می‌شود `{'train.C': 0.1}`. تابع بازگشتی (recursive) است، یعنی برای دیکشنری‌های داخلی خودش را دوباره صدا می‌زند و با هر عمقی کار می‌کند. اگر `flatten` خراب شود، نام پارامترها در UI عوض می‌شود.

### تابع `data_md5`

```python
dvc_file = pathlib.Path(raw_path + ".dvc")
if not dvc_file.exists():
    return "unknown"
return yaml.safe_load(dvc_file.read_text())["outs"][0]["md5"]
```

ابزار DVC برای هر نسخه‌ی داده یک اثر انگشت (md5) در فایل `churn.csv.dvc` ثبت می‌کند. آن را به‌عنوان tag در run می‌گذاریم تا بعداً بدانیم این مدل با کدام نسخه‌ی داده ساخته شده است؛ یعنی داده، کد و پارامتر با هم ردیابی می‌شوند. فایل `.dvc` یک YAML است که `outs` آن فهرست است و عنصر اولش همان داده‌ی ماست. اگر فایل نبود (مثلاً در تست)، مقدار `"unknown"` برمی‌گردد و خطا نمی‌دهد.

### تابع `tracking_uri`

```python
return os.environ.get("MLFLOW_TRACKING_URI", DEFAULT_URI)
```

آدرس سرور را از متغیر محیطی (فایل `.env`) می‌خوانیم تا بدون تغییر کد بتوان به سرور دیگری وصل شد. مثلاً تست‌ها آن را روی یک فایل SQLite موقت می‌گذارند.

### تابع `check_server`

```python
try:
    requests.get(f"{uri}/health", timeout=3).raise_for_status()
except requests.RequestException as e:
    raise SystemExit(
        f"MLflow server not reachable at {uri} ({type(e).__name__}).\n"
        "Start it: cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"
    ) from e
```

اگر سرور MLflow خاموش باشد، خود MLflow چند دقیقه تلاش مجدد می‌کند و دانشجو فقط یک خطای طولانی و گیج‌کننده می‌بیند. این تابع قبلش با یک درخواست ساده به `/health` (حداکثر ۳ ثانیه) سرور را می‌آزماید و در صورت مشکل با پیام روشن متوقف می‌شود.

دلیل مهم‌تر: اگر بی‌صدا از ثبت صرف‌نظر می‌کردیم، `dvc repro` موفق می‌شد ولی run گم می‌شد؛ و چون DVC دفعه‌ی بعد تغییری نمی‌بیند، `evaluate` دوباره اجرا نمی‌شد. پس خطا بهتر است. `SystemExit` با یک رشته برنامه را با همان پیام و بدون traceback طولانی متوقف می‌کند و `from e` علت اصلی را به استثنای جدید وصل می‌کند. اگر آدرس با `http` شروع نشود (مثلاً `sqlite:///...` در تست‌ها)، سرور HTTP وجود ندارد و بررسی رد می‌شود.

### تابع `log_run`

```python
mlflow.set_tracking_uri(uri)
mlflow.set_experiment(EXPERIMENT)
run_name = f"C={p['train']['C']} thr={p['eval']['threshold']}"
with mlflow.start_run(run_name=run_name) as run:
    mlflow.log_params(flatten(p))
    mlflow.log_metrics(metrics)
    mlflow.set_tag("data_md5", data_md5(p["data"]["raw_path"]))
    mlflow.log_artifact("metrics.json")
    mlflow.log_artifact(config)
```

این تابع هسته‌ی جلسه است. ابتدا به کلاینت می‌گوییم کجا بنویسد و experiment را انتخاب می‌کنیم (اگر نبود ساخته می‌شود). سپس داخل یک run ثبت می‌کنیم: `params` تنظیمات (C، threshold، seed و ...) تا بدانیم نتیجه با چه تنظیماتی آمده، `metrics` عددهای ارزیابی، tag به نام `data_md5` نسخه‌ی داده، و `artifacts` فایل‌های `metrics.json` و `params.yaml`. بلوک `with` تضمین می‌کند run در پایان، حتی با خطا، درست بسته شود (FINISHED یا FAILED). commit گیت را خود MLflow ثبت می‌کند و ما فقط نسخه‌ی داده را اضافه می‌کنیم. همه‌ی پارامترها در MLflow به‌صورت رشته ذخیره می‌شوند.

```python
mlflow.sklearn.log_model(
    model,
    name="model",
    signature=infer_signature(X, model.predict_proba(X)[:, 1]),
    input_example=X.head(5),
)
```

این بخش خود مدل را در قالب MLflow ذخیره می‌کند. `name="model"` نام مدل ثبت‌شده است. `signature` نوع و نام ستون‌های ورودی و خروجی است که از روی داده‌ی نمونه حدس زده می‌شود (خروجی ما احتمال ترک است)؛ بعداً یک سرویس می‌تواند ورودی نادرست را با آن تشخیص دهد. `input_example` پنج سطر نمونه‌ی ورودی است که کنار مدل ذخیره می‌شود. تابع در پایان شناسه‌ی run را برمی‌گرداند.

### تابع `main`

```python
pathlib.Path("metrics.json").write_text(json.dumps(metrics, indent=2))
print(metrics)
run_id = log_run(model, df, p, metrics, config)
```

ترتیب مهم است: اول `metrics.json` نوشته می‌شود، چون `log_run` آن را به‌عنوان artifact می‌خواند. در پیام پایانی `run_id[:8]` فقط هشت کاراکتر اول شناسه را چاپ می‌کند.

## فایل `scripts/list_runs.py`

**کار فایل:** بدون باز کردن مرورگر، runهای experiment به نام `churn` را در ترمینال به‌صورت جدول کوچک نشان می‌دهد: نام run، مقدار C، threshold، roc_auc و f1، با جدیدترین run در بالا.

**نحوه‌ی اجرا** (سرور MLflow باید روشن باشد):

```bash
make runs
```

**ورودی و خروجی:** ورودی runهای ثبت‌شده در MLflow است. خروجی فقط چاپ روی صفحه است و چیزی نوشته نمی‌شود. از توابع `churn.evaluate` استفاده می‌کند، پس همان بررسی سالم بودن سرور اینجا هم هست.

```python
runs = mlflow.search_runs(experiment_names=[EXPERIMENT], order_by=["start_time DESC"])
```

تابع `search_runs` یک DataFrame برمی‌گرداند که هر سطرش یک run است. ستون‌ها نام‌های بلند دارند: `params.*` پارامترها، `metrics.*` عددها و `tags.*` برچسب‌ها. گزینه‌ی `order_by` مرتب‌سازی را سمت سرور انجام می‌دهد و `start_time DESC` یعنی جدیدترین اول.

```python
names = {
    "run_id": "run_id",
    "tags.mlflow.runName": "name",
    "params.train.C": "C",
    "params.eval.threshold": "threshold",
    "metrics.roc_auc": "roc_auc",
    "metrics.f1": "f1",
}
```

این نقشه‌ی «نام ستون در MLflow به نام کوتاه برای نمایش» است.

```python
if runs.empty:
    print(f"no runs in experiment '{EXPERIMENT}' yet: run the pipeline first (make train)")
else:
    table = runs.reindex(columns=list(names)).rename(columns=names)
    table["run_id"] = table["run_id"].str[:8]
    print(table.to_string(index=False))
```

اگر هنوز runی نباشد، به‌جای خطای `KeyError` یک پیام روشن چاپ می‌شود. در غیر این صورت `list(names)` کلیدهای دیکشنری را می‌دهد و فقط همین ستون‌ها نگه داشته می‌شوند. استفاده از `reindex` به‌جای براکت مهم است: اگر ستونی هنوز در هیچ runی نباشد (مثلاً runی که پیش از ثبت پارامترها شکست خورده)، آن ستون خالی (NaN) نشان داده می‌شود و برنامه نمی‌شکند. شناسه‌ی run ۳۲ کاراکتر است و هشت کاراکتر اول برای نمایش کافی است. گزینه‌ی `index=False` شماره‌ی سطر را چاپ نمی‌کند.

## فایل `tests/test_tracking.py`

**کار فایل:** کد ثبت در MLflow را می‌سنجد. نکته‌ی مهم این است که این تست‌ها به سرور MLflow و Docker نیاز ندارند. به‌جای سرور، یک پایگاه داده‌ی SQLite موقت در پوشه‌ی موقت pytest ساخته می‌شود؛ پس همه‌جا، حتی بدون اینترنت و بدون compose، اجرا می‌شوند.

**نحوه‌ی اجرا:**

```bash
make test
```

تست `log_run` کندتر است (حدود ۲۰ ثانیه) چون ذخیره‌ی مدل در MLflow کار سنگینی است.

### تست `test_flatten_nested_params`

```python
assert flatten({"train": {"C": 0.1, "max_iter": 500}, "seed": 1}) == {
    "train.C": 0.1,
    "train.max_iter": 500,
    "seed": 1,
}
```

اگر `flatten` خراب شود، نام پارامترها در UI عوض می‌شود (مثلاً `train.C` نمی‌ماند) و `list_runs.py` ستون C را پیدا نمی‌کند.

### تست `test_check_server_fails_fast_when_server_is_down`

```python
with pytest.raises(SystemExit, match="not reachable"):
    check_server("http://127.0.0.1:1")
```

روی پورت ۱ هیچ سرویسی گوش نمی‌دهد، پس اتصال بلافاصله رد می‌شود. انتظار داریم `SystemExit` با متنی شامل `not reachable` بیاید؛ گزینه‌ی `match` متن پیام را با regex می‌سنجد. برای دانشجو مهم است که به‌جای چند دقیقه انتظار، پیام روشن ببیند.

### تست `test_log_run_writes_params_metrics_and_artifacts`

```python
monkeypatch.chdir(tmp_path)
monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{tmp_path}/mlflow.db")
```

این تست کل مسیر ثبت را واقعاً اجرا می‌کند، ولی روی SQLite موقت. دو fixture از pytest استفاده شده: `tmp_path` یک پوشه‌ی موقت یکتا برای همین تست می‌دهد، و `monkeypatch` محیط (پوشه‌ی جاری و متغیر محیطی) را موقتاً تغییر می‌دهد و بعد از تست خودکار برمی‌گرداند. پس به پروژه و `.env` واقعی دانشجو دست نمی‌زند. تغییر پوشه‌ی جاری باعث می‌شود فایل‌های `metrics.json` و `mlruns` در پروژه‌ی واقعی ساخته نشوند.

```python
client = mlflow.MlflowClient()
run = client.get_run(run_id)
assert run.data.params["train.C"] == "0.5"
assert run.data.tags["data_md5"] == "unknown"
```

کلاس `MlflowClient` برای خواندن چیزهایی است که ثبت شده و آدرس را از همان متغیر محیطی می‌گیرد. MLflow همه‌ی پارامترها را رشته ذخیره می‌کند، پس مقدار `"0.5"` است نه عدد `0.5`. فایل `churn.csv.dvc` در پوشه‌ی موقت نیست، پس md5 برابر `"unknown"` است.

```python
logged = client.search_logged_models(experiment_ids=[run.info.experiment_id])
assert [m.source_run_id for m in logged] == [run_id]
```

در MLflow 3 مدل در artifactهای run نیست؛ به‌صورت «logged model» جدا ثبت می‌شود. باید دقیقاً یک مدل باشد و منبعش همین run.

## فایل `Makefile`

```makefile
runs:
	uv run python scripts/list_runs.py
```

در این جلسه هدف تازه‌ی `runs` اضافه شده که جدول runها را چاپ می‌کند. هدف `train` همچنان `uv run dvc repro` است، ولی حالا مرحله‌ی evaluate هر بار یک run در MLflow هم ثبت می‌کند، پس سرور MLflow باید روشن باشد. هدف `test` به سرور نیاز ندارد. یادآوری: خط‌های دستور (recipe) باید با TAB شروع شوند.

## پرسش‌هایی برای فکر کردن

- اگر `check_server` وجود نداشت و سرور خاموش بود، چه بلایی سر `dvc repro` و نتیجه‌ی آزمایش می‌آمد؟
- چرا `flatten` بازگشتی نوشته شده و اگر بخش‌های `params.yaml` سه سطح تو در تو بودند چه می‌شد؟
- چه فرقی دارد که تست‌ها از SQLite موقت استفاده کنند یا از سرور واقعی روی پورت ۵۰۵۰؟
