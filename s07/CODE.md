<div dir="rtl">

# توضیح کد جلسه‌ی ۷

در جلسه‌ی ۶ هر آموزش مدل یک run در MLflow ساخت. در این جلسه تصمیم می‌گیریم کدام مدل «رسمی» است و در production استفاده می‌شود. برای این کار از **Model Registry** و دو **alias** استفاده می‌کنیم.

فایل‌های این جلسه:

- فایل `churn/registry.py`: ثبت مدل، alias، دروازه‌ی ارزیابی (gate) و ارتقا (promote). مهم‌ترین فایل جلسه است.
- فایل `scripts/predict_champion.py`: لود `models:/churn@champion` و پیش‌بینی پنج ردیف.
- فایل `scripts/shap_plot.py`: اختیاری، نمودار SHAP برای توضیح مدل.
- فایل `tests/test_registry.py`: چهار تست (سه تست gate و یک تست کامل register و promote).
- فایل `Makefile`: هدف‌های تازه‌ی `register`، `promote`، `models` و `predict`.

ارتباط با جلسه‌ها: `registry.py` از `churn/evaluate.py` (جلسه‌ی ۶) استفاده می‌کند. در جلسه‌ی ۸ فایل `churn/api.py` همین `connect` و `check_download_setting` را برمی‌دارد و مدل `@champion` را از همین Registry لود می‌کند.

کامنت‌ها و docstringهای داخل کد عمداً انگلیسی هستند، چون ویرایشگرهای کد متن را چپ‌به‌راست نشان می‌دهند. شرح فارسی همه‌چیز در همین فایل است.

---

## جریان کلی: challenger، gate، champion

قبل از دیدن کد، این تصویر را در ذهن داشته باشید:

```text
run (جلسه ۶)  --register-->  نسخه‌ی N از churn  +  @challenger
                                      |
                                   promote
                                      |
                              gate (قوانین params.yaml)
                               /                 \
                         قبول شد                رد شد
                  @champion به نسخه‌ی N      @champion سر جای خودش
                      منتقل می‌شود          (tag: gate=failed)
```

- مفهوم `alias` یک برچسب متحرک روی یک نسخه است، مثل برچسب `latest` در Docker.
- برچسب `@challenger` یعنی «مدل تازه، هنوز امتحان نشده».
- برچسب `@champion` یعنی «مدلی که رسماً استفاده می‌شود».
- ارتقا فقط جابه‌جا کردن یک برچسب است. هیچ فایلی کپی نمی‌شود.
- هیچ‌جا شماره‌ی نسخه را در کد ننوشته‌ایم؛ فقط اسم alias را می‌نویسیم. به همین دلیل با عوض شدن champion، کد دیگران (مثل API) عوض نمی‌شود.

---

## فایل `churn/registry.py`

**کار فایل:** سه کار اصلی دارد: `register` (ثبت مدل یک run و گذاشتن `@challenger`)، `promote` (سنجیدن با gate و انتقال `@champion`) و `show` (چاپ جدول نسخه‌ها).

**اجرا** (از ریشه‌ی پروژه):

```bash
make register RUN=1a2b3c4d
make promote
make models
```

مقدار `RUN` همان ۸ حرف اول شناسه‌ی run است که `make runs` چاپ می‌کند.

**ورودی و خروجی:** ورودی سرور MLflow و بخش `gate` در `params.yaml` است. خروجی نسخه‌ی مدل، tagها و aliasها در Registry است (داخل SQLite سرور MLflow). فایل‌های مدل در `s3://mlflow/` می‌مانند.

### ثابت‌ها

```python
MODEL_NAME = "churn"
# Alias names are plain strings; the code never hard-codes a version number.
CHALLENGER = "challenger"
CHAMPION = "champion"
```

یک مدل ثبت‌شده فقط یک اسم دارد (`churn`) و چند نسخه (۱، ۲، ۳ و ...). اسم aliasها رشته‌ی ساده‌اند. کد هیچ‌وقت شماره‌ی نسخه را سخت‌کد نمی‌کند.

### تابع `connect`

```python
def connect() -> MlflowClient:
    uri = tracking_uri()
    check_server(uri)  # fails early with a clear message if the server is down
    # Global setting: after this, mlflow.register_model / load_model use this server.
    mlflow.set_tracking_uri(uri)
    return MlflowClient()
```

این تابع اول چک می‌کند سرور MLflow واقعاً بالا است. اگر نباشد، برنامه با پیام روشن تمام می‌شود و traceback طولانی نمی‌بینید. بعد آدرس سرور را برای همه‌ی توابع `mlflow.*` تنظیم می‌کند. آخر یک `MlflowClient` برمی‌گرداند؛ این همان شیئی است که با Registry (نسخه‌ها، aliasها و tagها) کار می‌کند.

### تابع `check_download_setting` و مشکل hang

```python
def check_download_setting() -> None:
    # .lower() so "False", "FALSE" and "false" are all accepted; missing -> "" -> error
    if os.environ.get("MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD", "").lower() != "false":
        # SystemExit (not Exception): in a script it stops the program and prints the message
        # without a long traceback, which is friendlier for a student.
        raise SystemExit(
            "MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false is not set: load_model would hang.\n"
            "Fix: set -a; source .env; set +a"
        )
```

این تابع یکی از مهم‌ترین درس‌های جلسه است. ماجرا این است:

1. وقتی `mlflow.sklearn.load_model` فایل مدل را از S3 دانلود می‌کند، سرور MLflow یک لینک امضاشده (presigned URL) به برنامه می‌دهد.
2. این لینک آدرس `http://seaweedfs...` دارد. این اسم فقط داخل شبکه‌ی Docker شناخته می‌شود.
3. از لپ‌تاپ شما این آدرس قابل دسترسی نیست، پس دانلود **بدون هیچ خطایی برای همیشه گیر می‌کند** (hang). فقط نوار `Downloading artifacts: 0%` را می‌بینید.
4. با `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` مدل از طریق خود سرور MLflow (proxy) دانلود می‌شود و مشکل حل می‌شود.

هنگام آماده‌سازی جلسه این hang واقعاً دیده شد: بدون متغیر، دستور بعد از ۶۰ ثانیه فقط `0/7` نشان داد و با timeout کشته شد.

ما این تابع را **قبل از هر load_model** صدا می‌زنیم. نتیجه این است که به جای hang، یک پیام روشن می‌گیرید. متغیر در فایل `.env` است و با این دستور وارد ترمینال می‌شود:

```bash
set -a; source .env; set +a
```

چرا `SystemExit` و نه `Exception` معمولی؟ در یک اسکریپت، `SystemExit` برنامه را با همان پیام و بدون traceback تمام می‌کند. (در جلسه‌ی ۸ می‌بینید که این انتخاب در API یک نکته‌ی ظریف دارد.)

### تابع `find_run`

```python
    exp = client.get_experiment_by_name(EXPERIMENT)
    if exp is None:
        raise SystemExit(f"experiment '{EXPERIMENT}' not found: run the pipeline first")
    # List comprehension with a filter: keep only runs whose id starts with the prefix.
    # MLflow cannot search by "id starts with", so we fetch (up to 1000) and filter in Python.
    runs = [
        r
        for r in client.search_runs([exp.experiment_id], max_results=1000)
        if r.info.run_id.startswith(prefix)
    ]
    if len(runs) != 1:  # 0 = typo, 2+ = prefix too short: both are unsafe to guess
        raise SystemExit(f"expected 1 run starting with '{prefix}', found {len(runs)}")
    return runs[0]
```

شناسه‌ی کامل run سی‌ودو حرف است و تایپش سخت است. `make runs` فقط ۸ حرف اول را نشان می‌دهد و ما هم همان را می‌پذیریم. MLflow جست‌وجوی «شروع با» ندارد، پس تا هزار run را می‌گیریم و در Python فیلتر می‌کنیم.

اگر هیچ run پیدا نشود (غلط تایپی) یا بیشتر از یکی پیدا شود (prefix کوتاه است)، حدس نمی‌زنیم و با پیام روشن تمام می‌کنیم. حدس زدن در کار ثبت مدل خطرناک است.

### تابع `get_alias`

```python
    try:
        return client.get_model_version_by_alias(MODEL_NAME, alias)
    except MlflowException:
        return None
```

وقتی alias هنوز ساخته نشده (مثلاً بار اول که `@champion` نداریم)، MLflow خطای `MlflowException` می‌دهد. ما آن را به `None` تبدیل می‌کنیم تا بقیه‌ی کد با یک `if` ساده بگوید «هنوز champion نداریم».

### تابع `release_note`

```python
    m, p, t = run.data.metrics, run.data.params, run.data.tags
    # [:7] = short git hash; "unknown" is the fallback if MLflow could not read git
    commit = t.get("mlflow.source.git.commit", "unknown")[:7]
    return (
        f"LogisticRegression C={p.get('train.C')} threshold={p.get('eval.threshold')}. "
        f"roc_auc={m['roc_auc']} f1={m['f1']}. "
        f"data md5 {t.get('data_md5', 'unknown')[:8]}, git commit {commit}, "
        f"run {run.info.run_id[:8]}."
    )
```

این متن به‌عنوان توضیح (description) روی نسخه‌ی مدل نوشته می‌شود و در UI دیده می‌شود. هر کسی بعداً می‌فهمد این نسخه با چه hyperparameter، چه metric، روی کدام داده (md5) و کدام commit گیت ساخته شده است. این یعنی ردگیری کامل: مدل، run، داده، کد.

### تابع `register`

```python
    run = find_run(client, prefix)
    # MLflow 3 logs each trained model as a "logged model" with its own id; the run keeps
    # a list of its outputs, and the first one is our sklearn pipeline.
    model_id = run.outputs.model_outputs[0].model_id
    # Creates version N of 'churn' from that logged model (no re-upload of the files).
    mv = mlflow.register_model(f"models:/{model_id}", MODEL_NAME)
    client.update_model_version(MODEL_NAME, mv.version, description=release_note(run))
```

مراحل ثبت:

1. ابتدا run را پیدا می‌کنیم.
2. مدلِ لاگ‌شده‌ی همان run را برمی‌داریم. در MLflow 3 هر مدل آموزش‌دیده یک «logged model» با شناسه‌ی خودش است.
3. تابع `register_model` نسخه‌ی جدید `churn` را می‌سازد. شماره‌ها خودکار ۱، ۲، ۳ و ... می‌شوند و فایل‌ها دوباره آپلود نمی‌شوند.
4. توضیح را روی نسخه می‌نویسیم.

```python
    for key in ("roc_auc", "f1"):
        client.set_model_version_tag(MODEL_NAME, mv.version, key, run.data.metrics[key])
    client.set_model_version_tag(MODEL_NAME, mv.version, "train.C", run.data.params["train.C"])
    client.set_model_version_tag(MODEL_NAME, mv.version, "data_md5", run.data.tags["data_md5"])
    # If @challenger already pointed to an older version, it simply moves to this one.
    client.set_registered_model_alias(MODEL_NAME, CHALLENGER, mv.version)
```

برچسب‌های tag رشته‌های کلید و مقدار قابل جست‌وجو روی نسخه هستند. عددها را اینجا هم کپی می‌کنیم تا `show` و `promote` بدون باز کردن run بتوانند آن‌ها را چاپ کنند. در آخر `@challenger` به این نسخه می‌رود. اگر قبلاً روی نسخه‌ی قدیمی‌تر بود، همین‌طور جابه‌جا می‌شود.

نکته‌ی مهم: `register` **هیچ‌وقت** `@champion` را عوض نمی‌کند. ارتقا فقط کار `promote` است، آن هم بعد از gate.

### تابع `gate`

```python
def gate(challenger: dict, champion: dict | None, rules: dict) -> list[str]:
    failed = []
    if challenger["roc_auc"] < rules["min_roc_auc"]:
        failed.append(f"roc_auc {challenger['roc_auc']} < min_roc_auc {rules['min_roc_auc']}")
    if challenger["f1"] < rules["min_f1"]:
        failed.append(f"f1 {challenger['f1']} < min_f1 {rules['min_f1']}")
    if champion is not None:  # the "no regression" rule only makes sense if a champion exists
        # round(..., 4): avoids float noise such as 0.7482999999 in the comparison
        floor = round(champion["roc_auc"] - rules["max_roc_auc_drop"], 4)
        if challenger["roc_auc"] < floor:
            failed.append(
                f"roc_auc {challenger['roc_auc']} < champion {champion['roc_auc']}"
                f" - max_roc_auc_drop {rules['max_roc_auc_drop']}"
            )
    return failed
```

این «دروازه‌ی کیفیت» است. مهم‌ترین ویژگی‌اش این است که **هیچ ارتباطی با MLflow ندارد**: فقط چند عدد را با قوانین مقایسه می‌کند (یک «تابع خالص»). به همین دلیل بدون سرور و خیلی راحت تست می‌شود.

سه قانون دارد که مقدارشان در بخش `gate` فایل `params.yaml` است:

1. قانون `min_roc_auc`: کف مطلق برای roc_auc.
2. قانون `min_f1`: کف مطلق برای f1.
3. قانون `max_roc_auc_drop`: اگر champion داریم، roc_auc مدل جدید نباید بیشتر از این مقدار از champion کمتر باشد. افت کوچک قابل قبول است، افت بزرگ نه.

خروجی یک فهرست از پیام‌های شکست است. فهرست خالی یعنی «قبول». gate همه‌ی قانون‌ها را جدا چک می‌کند و **همه‌ی** خطاها را برمی‌گرداند، نه فقط اولی. دلیلش این است که ممکن است f1 بهتر شود ولی roc_auc بد شود، و باید بدانید دقیقاً چه چیزهایی خراب است.

عبارت `round(..., 4)` برای این است که خطای ممیز شناور (مثل `0.7482999999`) مقایسه را خراب نکند.

### تابع‌های `metrics_of` و `promote`

```python
def metrics_of(client: MlflowClient, mv) -> dict:
    return client.get_run(mv.run_id).data.metrics
```

مقدار metricها را از خود run می‌خوانیم، نه از tag، چون run منبع اصلی حقیقت است.

```python
    chal = get_alias(client, CHALLENGER)
    if chal is None:
        raise SystemExit(f"no @{CHALLENGER} yet: make register RUN=<run id>")
    champ = get_alias(client, CHAMPION)  # None the first time
    # str(...) on both sides: versions can be int or str depending on the MLflow call
    if champ is not None and str(champ.version) == str(chal.version):
        print(f"version {chal.version} is already @{CHAMPION}")
        return True
```

مراحل `promote`:

1. نسخه‌ی challenger را می‌خوانیم. اگر نبود، خطای روشن می‌دهیم.
2. اگر همین نسخه همین الان champion است، کاری نمی‌کنیم.
3. مقدار metricهای challenger و champion فعلی را چاپ می‌کنیم.
4. تابع `gate` را اجرا می‌کنیم.
5. فقط اگر قبول شد، `@champion` را جابه‌جا می‌کنیم.

دلیل `str(...)` دو طرف: در SQLite شماره‌ی نسخه گاهی `int` و گاهی `str` برمی‌گردد. این یک باگ واقعی بود که هنگام نوشتن تست پیدا شد.

```python
    failed = gate(c_metrics, old, rules)
    # The verdict is stored on the version, so it is visible later in `make models` and the UI
    client.set_model_version_tag(MODEL_NAME, chal.version, "gate", "failed" if failed else "passed")
    if failed:
        for reason in failed:
            print(f"  FAIL {reason}")
        # a failed gate does NOT touch @champion: production keeps the old model
        print(f"gate FAILED: @{CHAMPION} stays on version {champ.version if champ else '-'}")
        return False
    # The actual promotion is just moving an alias: no files are copied.
    client.set_registered_model_alias(MODEL_NAME, CHAMPION, chal.version)
    print(f"gate passed: @{CHAMPION} -> version {chal.version}")
    return True
```

نتیجه‌ی gate (`passed` یا `failed`) به‌صورت tag روی نسخه نوشته می‌شود، پس بعداً در `make models` و UI دیده می‌شود. وقتی gate رد کند، `@champion` دست‌نخورده می‌ماند و production همان مدل قبلی را نگه می‌دارد. ارتقای واقعی فقط یک خط است: جابه‌جا کردن alias.

مقدار برگشتی `True` یا `False` است. تابع `main` مقدار `False` را به exit code برابر ۱ تبدیل می‌کند تا `make promote` خطا نشان دهد و CI هم بتواند شکست gate را تشخیص دهد.

### تابع `show`

```python
    # dict like {"champion": "2", "challenger": "3"}: alias name -> version number
    aliases = client.get_registered_model(MODEL_NAME).aliases
    # Format spec: >7 right-align in 7 chars, 8 = pad to 8 chars (left-aligned for strings)
    print(f"{'version':>7} {'run':8} {'C':>6} {'roc_auc':>7} {'f1':>6} {'gate':6}  aliases")
    # key=int(...): sort numerically (so version 10 comes after 9, not after 1)
    for mv in sorted(versions, key=lambda v: int(v.version)):
```

این همان خروجی `make models` است: هر ردیف یک نسخه و ستون آخر aliasهای آن نسخه (مثلاً `@champion`). مرتب‌سازی با `int(...)` عددی است تا نسخه‌ی ۱۰ بعد از ۹ بیاید، نه بعد از ۱.

### تابع `main`

```python
    ap = argparse.ArgumentParser()
    # dest="cmd": the chosen sub-command name is saved in args.cmd; required=True: no default
    sub = ap.add_subparsers(dest="cmd", required=True)
    reg = sub.add_parser("register")
    reg.add_argument("--run", required=True, help="run id or its first 8 characters")
    pro = sub.add_parser("promote")
    pro.add_argument("--config", default="params.yaml")
    sub.add_parser("show")
```

از `argparse` با زیردستور (subparser) استفاده شده، مثل `git commit` و `git push` که هر کدام گزینه‌های خودشان را دارند. `promote` فایل `params.yaml` را با `yaml.safe_load` می‌خواند (بدون اجرای کد دلخواه) و بخش `["gate"]` را برمی‌دارد. اگر این بخش در `params.yaml` نباشد، خطای `KeyError: 'gate'` می‌گیرید؛ این اتفاق وقتی افتاد که بعد از یک آزمایش `git restore params.yaml` بخش commit‌نشده را پاک کرد. راه‌حل: بخش `gate` را اضافه کنید و **قبل از** `dvc exp run` commit کنید.

آخر هر اجرا (حتی `show`) جدول نسخه‌ها چاپ می‌شود.

---

## فایل `scripts/predict_champion.py`

**کار فایل:** ثابت می‌کند مدلی که با alias به نام `@champion` ثبت شده را می‌توان فقط با اسم لود کرد، بدون دانستن شناسه‌ی run یا شماره‌ی نسخه، و روی داده‌ی واقعی پیش‌بینی گرفت.

**اجرا** (بعد از `make register` و `make promote`):

```bash
make predict
```

**ورودی و خروجی:** ورودی سرور MLflow و فایل `data/processed/test.csv` است. خروجی فقط چاپ روی صفحه است (نسخه‌ی مدل، زمان لود، نام ستون‌های signature و احتمال churn برای ۵ ردیف). فایلی ساخته نمی‌شود.

```python
# Stop early with a clear message if the env variable that prevents the download hang is missing.
check_download_setting()
client = connect()
mv = client.get_model_version_by_alias(MODEL_NAME, CHAMPION)
uri = f"models:/{MODEL_NAME}@{CHAMPION}"  # e.g. models:/churn@champion
```

اول همان نگهبان hang را صدا می‌زنیم، بعد وصل می‌شویم. آدرس `models:/churn@champion` یعنی «مدل `churn` با alias به نام `champion`». نسخه را فقط برای چاپ می‌پرسیم.

```python
model = mlflow.sklearn.load_model(uri)
```

این خط فایل‌های مدل را از S3 (از طریق سرور MLflow) دانلود می‌کند و کل Pipeline را دوباره می‌سازد. چون پیش‌پردازش داخل همین Pipeline است، می‌توانیم ستون‌های خام را مستقیم بدهیم.

```python
info = mlflow.models.get_model_info(uri)
print("signature inputs:", [c.name for c in info.signature.inputs])
```

مفهوم signature «قرارداد ورودی» مدل است: نام و نوع ستون‌هایی که مدل با آن‌ها آموزش دیده. در جلسه‌ی ۸ از همین signature برای ساختن قرارداد API استفاده می‌شود.

```python
X = pd.read_csv(OUT_DIR / "test.csv").drop(columns=[TARGET]).head(5)
# predict_proba returns [P(stay), P(churn)] per row; [:, 1] keeps the churn column.
print("churn probability:", model.predict_proba(X)[:, 1].round(4).tolist())
```

ستون جواب (`churn`) را حذف می‌کنیم، چون مدل نباید جواب را ببیند. `predict_proba` برای هر ردیف دو عدد برمی‌گرداند و `[:, 1]` ستون احتمال churn را نگه می‌دارد.

در جلسه‌ی ۸ سرویس API همین کار را می‌کند، با این تفاوت که مدل را فقط یک بار هنگام شروع سرور لود می‌کند.

---

## فایل `scripts/shap_plot.py` (اختیاری)

**کار فایل:** «توضیح‌پذیری» (explainability) را نشان می‌دهد: کدام ویژگی‌ها بیشترین اثر را روی پیش‌بینی دارند؟ SHAP برای هر ردیف و هر feature یک عدد می‌دهد که نشان می‌دهد آن feature احتمال churn را چقدر بالا یا پایین برده است. نمودار beeswarm همه‌ی این عددها را یک‌جا نشان می‌دهد.

**اجرا:** این اسکریپت به بسته‌ی `shap` نیاز دارد که جزو وابستگی‌های پروژه نیست. بدون تغییر `pyproject.toml` اجرایش کنید:

```bash
uv run --with shap==0.54.1 python scripts/shap_plot.py
```

**ورودی و خروجی:** ورودی مدل `@champion` و `data/processed/test.csv` است. خروجی فایل `shap_summary.png` در پوشه‌ی جاری است و همان فایل به‌عنوان artifact روی run سازنده‌ی مدل champion آپلود می‌شود (در UI، تب Artifacts).

```python
import matplotlib

# "Agg" = draw into files only, never open a window. Must be set BEFORE importing pyplot,
# which is why the imports below carry "noqa: E402" (ruff: import not at top of file).
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
```

حالت backend به نام `Agg` یعنی «فقط در فایل بکش، پنجره باز نکن». باید قبل از import کردن `pyplot` تنظیم شود. به همین دلیل importهای بعدی `noqa: E402` دارند تا ruff شکایت نکند.

```python
pre, clf = model.named_steps["pre"], model.named_steps["clf"]
Xt = pre.transform(X)  # raw columns -> numbers (scaled + one-hot), exactly what clf saw
names = pre.get_feature_names_out()  # readable names such as "num__tenure_months"
# LinearExplainer is the exact and fast SHAP method for linear models like LogisticRegression.
explainer = shap.LinearExplainer(clf, Xt)
values = explainer(Xt)  # one SHAP value per row and per feature
```

مدل یک Pipeline با دو مرحله‌ی نام‌دار است: `pre` (پیش‌پردازش) و `clf` (طبقه‌بند LogisticRegression). SHAP ماتریس عددی و طبقه‌بند را جدا می‌خواهد، پس Pipeline را باز می‌کنیم. `LinearExplainer` روش دقیق و سریع SHAP برای مدل‌های خطی است.

```python
shap.plots.beeswarm(values, show=False, max_display=12)
plt.tight_layout()  # avoid cut-off labels
plt.savefig("shap_summary.png", dpi=120)
# Attach the picture to the run that trained the champion model (it shows up in the MLflow UI).
client.log_artifact(mv.run_id, "shap_summary.png")
```

گزینه‌ی `show=False` یعنی نمایش نده، خودمان ذخیره می‌کنیم. `max_display=12` فقط دوازده ویژگی مهم را نشان می‌دهد. `log_artifact` عکس را به run قدیمیِ سازنده‌ی مدل اضافه می‌کند؛ این روی run تمام‌شده هم کار می‌کند.

---

## فایل `tests/test_registry.py`

**کار فایل:** چهار تست برای `registry.py`. با `make test` اجرا می‌شوند و به سرور MLflow واقعی یا Docker نیاز ندارند، پس در CI هم اجرا می‌شوند.

**اجرا:**

```bash
make test
```

### قوانین تست

```python
# The same three rules as the `gate` section of params.yaml (values for the tests).
RULES = {"min_roc_auc": 0.745, "min_f1": 0.69, "max_roc_auc_drop": 0.001}
```

همان سه قانون `params.yaml`، این‌جا به‌صورت یک dict ثابت. چون `gate` تابع خالص است، تستش فقط عدد و قانون می‌خواهد.

### سه تست gate

```python
def test_gate_passes_first_model_above_the_floors():
    assert gate({"roc_auc": 0.7493, "f1": 0.701}, None, RULES) == []
```

اولین مدل (بدون champion) اگر از هر دو کف بالاتر باشد، قبول می‌شود (فهرست خالی).

```python
def test_gate_blocks_low_roc_auc_even_if_f1_is_higher():
    failed = gate({"roc_auc": 0.7358, "f1": 0.718}, {"roc_auc": 0.7493, "f1": 0.701}, RULES)
    assert len(failed) == 2
    assert failed[0].startswith("roc_auc 0.7358 < min_roc_auc")
```

درس اصلی gate: فقط یک metric را نگاه نکنید. این مدل f1 بهتری دارد ولی roc_auc ضعیف‌تر. دو قانون می‌شکنند (کف roc_auc و افت نسبت به champion)، پس دو پیام برمی‌گردد.

```python
    champion = {"roc_auc": 0.7493, "f1": 0.701}
    # 0.7493 - 0.001 = 0.7483 is the floor: 0.7489 is above it, 0.7480 is below it
    assert gate({"roc_auc": 0.7489, "f1": 0.7033}, champion, RULES) == []
    assert gate({"roc_auc": 0.7480, "f1": 0.7033}, champion, RULES) != []
```

افت خیلی کوچک تا `max_roc_auc_drop` قابل قبول است و افت بیشتر نه. این تست مرز دقیق را امتحان می‌کند.

### fixture به نام `one_run`

```python
@pytest.fixture
def one_run(tmp_path, monkeypatch):
    # a throw-away SQLite tracking store + registry in tmp_path: no server needed
    monkeypatch.chdir(tmp_path)  # log_run reads/writes relative files (metrics.json...)
    monkeypatch.setenv("MLFLOW_TRACKING_URI", f"sqlite:///{tmp_path}/mlflow.db")
```

مفهوم fixture کدی است که قبل از تست آماده‌سازی می‌کند. `tmp_path` پوشه‌ای موقت است که pytest می‌سازد و بعد پاک می‌کند. `monkeypatch` اجازه می‌دهد پوشه‌ی جاری و متغیر محیطی را فقط برای همین تست عوض کنیم و بعد خودکار برگردند. نتیجه: تست‌ها به داده و MLflow واقعی شما دست نمی‌زنند و یک Registry موقت (SQLite) در پوشه‌ی tmp دارند.

```python
    # 600 synthetic rows (seed=1) are enough for a quick, deterministic model
    train, test = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    model = build_model(X, **p["train"]).fit(X, train["churn"])  # **dict -> C=..., max_iter=...
```

با ۶۰۰ ردیف مصنوعی یک مدل کوچک و سریع و تکرارپذیر می‌سازیم. علامت `**` یک dict را به آرگومان‌های نام‌دار تبدیل می‌کند.

### تست کامل register و promote

```python
    run_id, metrics = one_run
    client = MlflowClient()  # uses MLFLOW_TRACKING_URI set by the fixture (the temp SQLite)
    mv = register(client, run_id[:8])  # the same 8-character prefix a student types in `make`
    assert int(mv.version) == 1  # first registration in a fresh registry
    assert client.get_model_version_by_alias(MODEL_NAME, CHALLENGER).run_id == run_id

    # Rules that everything passes, so this test checks the alias move, not the numbers.
    easy = {"min_roc_auc": 0.0, "min_f1": 0.0, "max_roc_auc_drop": 0.001}
    assert promote(client, easy) is True
```

این تست کل مسیر جلسه را می‌پوشاند: run، نسخه‌ی مدل، challenger، gate، champion. قوانین را عمداً آسان گذاشته‌ایم تا فقط جابه‌جا شدن aliasها آزموده شود، نه عددها. در آخر هم بررسی می‌کند tagهای `gate` و `roc_auc` روی نسخه نوشته شده‌اند. چون tagها همیشه رشته‌اند، با `str(metrics["roc_auc"])` مقایسه می‌شوند.

---

## فایل `Makefile`

**کار فایل:** میان‌بر دستورهای پروژه. در این جلسه چهار هدف تازه اضافه می‌شود. (Makefile جلسه‌ی قبل را جایگزین می‌کند.)

```makefile
register:
	uv run python -m churn.registry register --run $(RUN)
```

هدف `register`: مدل یک run را ثبت می‌کند و `@challenger` می‌گذارد. مقدار `RUN` را موقع اجرا می‌دهید: `make register RUN=1a2b3c4d`. اگر `RUN` خالی بماند، `argparse` خطای `expected one argument` می‌دهد.

```makefile
promote:
	uv run python -m churn.registry promote
```

هدف `promote`: gate را روی challenger اجرا می‌کند و اگر قبول شد `@champion` را منتقل می‌کند. اگر gate رد کند، exit code برابر ۱ است و `make` خطا نشان می‌دهد.

```makefile
models:
	uv run python -m churn.registry show
```

هدف `models`: جدول نسخه‌های `churn` را با metricها، نتیجه‌ی gate و aliasها چاپ می‌کند.

```makefile
predict:
	uv run python scripts/predict_champion.py
```

هدف `predict`: مدل `@champion` را لود می‌کند و برای ۵ ردیف تست پیش‌بینی می‌گیرد.

خط `.PHONY` به `make` می‌گوید این اسم‌ها فایل نیستند و همیشه باید اجرا شوند. توجه: جلوی خط‌های دستور داخل هر هدف باید یک کاراکتر TAB باشد، نه فاصله.

---

## پرسش‌هایی برای فکر کردن

1. چرا `register` فقط `@challenger` را می‌گذارد و کار گذاشتن `@champion` را به `promote` سپرده‌ایم؟ اگر یک تابع هر دو کار را می‌کرد چه خطری داشت؟
2. چرا تابع `gate` عمداً به MLflow وصل نیست؟ این انتخاب چه فایده‌ای در تست کردن دارد؟
3. اگر `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD` تنظیم نشده باشد و نگهبان `check_download_setting` وجود نداشت، دانشجو چه چیزی می‌دید و چقدر طول می‌کشید تا بفهمد مشکل چیست؟

</div>
