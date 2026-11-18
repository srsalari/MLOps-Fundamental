<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱۴ — اجرای سرتاسری از clone تمیز، Runbook و Demo

سیزده جلسه‌ی گذشته پروژه‌ی Churn را قطعه‌قطعه ساختید. سؤال امروز: **آیا این پروژه واقعاً مال شماست، یا فقط روی لپ‌تاپ شما و با حافظه‌ی شما کار می‌کند؟** یک هم‌تیمی تازه که فقط آدرس مخزن را دارد، می‌تواند سرویس را بالا بیاورد؟ پاسخ را با یک آزمایش ساده می‌گیریم: مخزن را در یک پوشه‌ی کاملاً تازه clone می‌کنیم (بدون `.venv`، بدون `.env`، بدون cache داده) و همه‌چیز را از اول اجرا می‌کنیم. هر چیزی که کم باشد همان لحظه پیدا می‌شود.

بعد با یک چک‌لیست امتیازدار می‌سنجیم پروژه چقدر «آماده‌ی production» است، Runbook و README را کامل می‌کنیم، نسخه‌ی `v1.0.0` را می‌زنیم و Demo پنج‌دقیقه‌ای می‌دهیم.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۱۳ سالم باشد: `~/work/churn-mlops` روی `main` با tag `v0.11.0` (CI، پوشه‌ی `monitoring/`، گزارش drift). این پوشه را **دست نزنید**؛ امروز کار روی یک clone تازه است.
2. این‌ها روشن باشند: سرویس‌های آزمایشگاه (SeaweedFS، MLflow، Gitea)، registry محلی (`localhost:5001`)، cluster جلسه‌ی ۱۱ و ۱۲ با Traefik و release نام `churn-api`، و (اگر هست) مانیتورینگ جلسه‌ی ۱۳. `docker compose down -v` نزده باشید.
3. **حافظه‌ی Docker حداقل ۶ گیگابایت.** ما کل زنجیره را (MLflow، SeaweedFS، registry، cluster، مانیتورینگ و یک API) با هم اندازه گرفتیم: حدود ۳٫۶ گیگابایت.
4. اینترنت یا PyPI mirror: clone تازه `uv sync` را از اول می‌زند و بار اول کتابخانه‌ها را دانلود می‌کند (حدود ۷۰ ثانیه در آزمایش ما).
5. <bdi dir="rtl">image‌های Prometheus و Grafana (و بقیه) روی لپ‌تاپ باشند. بدون آن‌ها بار اول حدود ۱٫۷۵ گیگابایت دانلود می‌شود (در آزمایش ما حدود ۳ دقیقه).</bdi>
6. بررسی آمادگی:

```bash
~/mlops-lab/s14/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید:

```bash
git -C ~/mlops-lab pull
```

> دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell.

## مفهوم‌ها در یک نگاه

| مفهوم | یک جمله |
| --- | --- |
| **clone تمیز** | پوشه‌ای که فقط محتوای Git را دارد. هر چه از Git نیامده (کلیدها، داده، venv) باید از جای درست برسد، یا پروژه بازتولیدپذیر نیست |
| **چک‌لیست آمادگی** | ۳۴ آیتم، ۱۰۰ امتیاز؛ هر آیتم با یک دستور سنجیده می‌شود (فایل `PRODUCTION-READINESS.md`) |
| **Runbook** | سند عملیات: چطور سرویس را روشن، خاموش، راه‌اندازی دوباره و برگردان کنیم و لاگ را کجا ببینیم. برای کسی که ساعت سه نیمه‌شب بیدار شده و پروژه را نمی‌شناسد |
| **Demo** | پنج دقیقه که نشان می‌دهد پروژه کار می‌کند، خراب می‌شود و برمی‌گردد. هر ادعا یک مدرک روی صفحه دارد |
| **نسخه‌ی `v1.0.0`** | نشانه‌ی «این نسخه تحویل شده است»؛ یک tag روی `main` |

مسیر امروز:

```text
Gitea  ->  git clone (~/work/churn-clean)  ->  .env + dvc pull + dvc repro --force
   ->  lint, test, image 1.0.0, scan, container  ->  registry  ->  helm upgrade (kind) -> Traefik
   ->  Prometheus/Grafana + drift  ->  readiness_check.sh  ->  RUNBOOK, DEMO, tag v1.0.0  ->  Demo
```

## نتیجه‌ی نهایی

- پوشه‌ی `~/work/churn-clean` که از صفر clone شده و کل زنجیره را اجرا کرده است
- <bdi dir="rtl">image به نام `churn-api:1.0.0` در registry و روی cluster</bdi>
- امتیاز آمادگی ۸۰ یا بیشتر از `scripts/readiness_check.sh`
- <bdi dir="rtl">`README.md`، `RUNBOOK.md` و `DEMO.md` کامل (بدون جای‌نگهدار)</bdi>
- <bdi dir="rtl">tag `v1.0.0` روی `main`، و یک Demo پنج‌دقیقه‌ای</bdi>

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `scripts/readiness_check.sh` | پوشه‌ی `scripts/` | امتیازدهی خودکار به ۳۴ آیتم |
| `RUNBOOK.md` | ریشه‌ی پروژه (جای فایل کوچک جلسه‌ی ۱۰) | Runbook آماده برای سرویس Churn؛ فقط جای‌نگهدارها را پر می‌کنید |
| `DEMO.md` | ریشه‌ی پروژه | متن Demo پنج‌دقیقه‌ای با زمان‌بندی |
| `README.project.md` | ریشه‌ی پروژه با نام `README.md` | صفحه‌ی اول مخزن (تا حالا خالی بود) |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۱۳) | هدف‌های تازه‌ی `demo-check` و `readiness` |
| `PRODUCTION-READINESS.md` | فقط بخوانید | فهرست آیتم‌ها، امتیاز، جلسه و دستور بررسی |
| `STORYTELLING.md` | فقط بخوانید | راهنمای Demo، جمله‌های رزومه، سؤال‌های دفاع |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

توضیح فایل‌ها به فارسی: [CODE.md](CODE.md).

---

## گام ۱ — clone تمیز، داده و pipeline (۱۸ دقیقه)

آدرس مخزن را از پروژه‌ی قدیمی می‌خوانیم (فقط خواندن) و در یک پوشه‌ی تازه clone می‌کنیم:

```bash
git clone "$(git -C ~/work/churn-mlops remote get-url origin)" ~/work/churn-clean
```

```bash
cd ~/work/churn-clean && git describe --tags
```

انتظار: `v0.11.0` (یا چیزی مثل `v0.11.0-2-g1a2b3c4` اگر تکلیف‌ها را merge کرده‌اید).

حالا ببینید چه چیزهایی **نیست**:

```bash
ls -a
```

انتظار: فایل‌های Git هست (`Makefile`، `chart`، `monitoring`، `.env.example`، …) ولی نه `.env`، نه `.venv`، نه `models/`، و در `data/raw/` فقط `churn.csv.dvc` (pointer) هست.

### کلیدها: فایل `.env`

کلیدها در Git نمی‌آیند (جلسه‌ی ۳). نمونه را کپی کنید و کلیدهای آزمایشگاه را از `~/mlops-lab/compose/.env` بگیرید:

```bash
cp .env.example .env
```

```bash
KEY=$(sed -n 's/^S3_ACCESS_KEY=//p' ~/mlops-lab/compose/.env); SECRET=$(sed -n 's/^S3_SECRET_KEY=//p' ~/mlops-lab/compose/.env)
```

```bash
grep -v -e '^AWS_ACCESS_KEY_ID=' -e '^AWS_SECRET_ACCESS_KEY=' .env > .env.tmp && mv .env.tmp .env
```

```bash
printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$KEY" "$SECRET" >> .env
```

```bash
cat >> .env <<'EOF'
MLFLOW_TRACKING_URI=http://localhost:5050
MLFLOW_DISABLE_AGENT_HINT=1
MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false
EOF
```

```bash
set -a; source .env; set +a
```

> رمز را با `cat .env` روی صفحه نیاورید (جلسه‌ی پخش صفحه یا ضبط ویدئو ممکن است در کار باشد).

### کتابخانه‌ها و کلیدهای DVC

```bash
uv sync
```

انتظار: چند ده سطر `+ نام==نسخه` و در پایان `Installed ... packages`. (`.venv` از صفر ساخته می‌شود؛ بار اول حدود ۷۰ ثانیه.)

فایل `.dvc/config` در Git هست (آدرس remote)، ولی کلیدها نه. دو دستور جلسه‌ی ۴:

```bash
uv run dvc remote modify --local storage access_key_id "$AWS_ACCESS_KEY_ID"
```

```bash
uv run dvc remote modify --local storage secret_access_key "$AWS_SECRET_ACCESS_KEY"
```

### داده، مدل و pipeline

```bash
uv run dvc pull
```

انتظار: `5 files fetched and 4 files added` (عددها کمی فرق کند، مشکلی نیست). این دستور هم داده و هم `models/model.joblib` را از S3 می‌آورد.

```bash
uv run dvc repro
```

انتظار: `Data and pipelines are up to date.` و **هیچ run تازه‌ای در MLflow ساخته نمی‌شود**. این رفتار درست DVC است: همه‌چیز همان است که در `dvc.lock` ثبت شده. ولی ما می‌خواهیم ثابت کنیم این کد روی ماشین تازه همان عددها را می‌سازد، پس اجرای اجباری:

```bash
uv run dvc repro --force
```

انتظار (حدود یک دقیقه): سه stage اجرا می‌شود و در آخر چیزی مثل `{'roc_auc': 0.7493, 'f1': 0.701}` و خط `mlflow: run ... logged to experiment 'churn'`.

```bash
uv run dvc metrics show
```

انتظار: `metrics.json  0.701  0.7493` (عدد شما همان است که در `~/work/churn-mlops/metrics.json` دارید). **اگر دو عدد برابرند، بازتولید ثابت شد.**

```bash
make runs
```

انتظار: جدول runها و در آخر یک run تازه. (`make register` و `make promote` را نزنید: `@champion` فعلی شما سالم است. روی یک ماشین کاملاً نو با MLflow خالی این دو دستور لازم‌اند؛ مدرس نشان می‌دهد.)

> **زمان:** تا دقیقه‌ی ۱۸ باید اینجا باشید.

---

## گام ۲ — کیفیت، image، scan و اجرای container (۱۲ دقیقه)

```bash
make lint
```

انتظار: `All checks passed!` و `... files already formatted`.

```bash
make test
```

انتظار: `26 passed` (یا بیشتر اگر تست اضافه کرده‌اید؛ حدود ۳۰ ثانیه).

<bdi dir="rtl">image با **tag تازه‌ی `1.0.0`** ساخته می‌شود تا با `0.7.0` قدیمی قاطی نشود:</bdi>

```bash
make image TAG=1.0.0
```

انتظار: چند دقیقه حداکثر؛ آخرش `naming to docker.io/library/churn-api:1.0.0`.

```bash
make scan TAG=1.0.0
```

انتظار: جدول‌هایی که ستون `Vulnerabilities` آن‌ها `0` است و بدون `Error`. اگر قرمز شد، جدول را بخوانید و کتابخانه‌ای را که `Fixed Version` دارد ارتقا دهید (جدول عیب‌یابی).

<bdi dir="rtl">container را کنار MLflow اجرا کنید. (دستور `make run-image` را اینجا **نمی‌زنیم**: نام و پورت ثابت دارد و با container قدیمی شما قاطی می‌شود.)</bdi>

```bash
docker run -d --name churn-clean-api --network mlops-lab -p 127.0.0.1:8011:8000 -e MLFLOW_TRACKING_URI=http://mlflow:5000 churn-api:1.0.0
```

```bash
curl -s http://localhost:8011/ready
```

انتظار (بعد از حدود ۱۰ ثانیه؛ اگر `connection reset` دیدید چند ثانیه صبر کنید): `{"status":"ready","model_version":"2"}`. شماره‌ی نسخه همان `@champion` شماست.

```bash
curl -s -X POST http://localhost:8011/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار: `{"churn_probability": ... ,"churn": ... ,"threshold":0.5,"model_version":"2"}`.

<bdi dir="rtl">container آزمایشی را پاک کنید (فقط همین یکی، با نام کامل) و image را به registry بفرستید:</bdi>

```bash
docker rm -f churn-clean-api
```

```bash
make push TAG=1.0.0
```

انتظار: `1.0.0: digest: sha256:... size: ...`.

> **زمان:** تا دقیقه‌ی ۳۰ باید اینجا باشید.

---

## گام ۳ — Kubernetes، Helm و Traefik (۱۵ دقیقه)

<bdi dir="rtl">cluster و Traefik از جلسه‌ی ۱۱ و ۱۲ هستند. اگر خاموش‌اند: `docker start kind-registry mlops-control-plane`.</bdi>

```bash
kubectl --context kind-mlops get nodes
```

انتظار: یک node با وضعیت `Ready`.

<bdi dir="rtl">release قبلی را با image تازه ارتقا دهید. این یک **revision جدید Helm** هم می‌سازد:</bdi>

```bash
make helm-deploy STAGE=dev HELM_ARGS="--set image.tag=1.0.0"
```

انتظار: `STATUS: deployed` و `REVISION: <عدد>`.

```bash
curl -s http://churn.localhost:8080/ready
```

```bash
make helm-status
```

انتظار: در جدول `helm list` ستون `UPDATED` تازه است، و پاد `1/1 Running` (یا همان تعداد replica که دارید).

```bash
kubectl --context kind-mlops -n churn get deployment churn-api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

انتظار: `localhost:5001/churn-api:1.0.0`. یعنی سرویس زنده از image‌ی ساخته شده در clone تمیز است.

### خرابی و بازگشت (هسته‌ی Demo)

عمداً یک مدل ناموجود بدهید. با `--timeout 30s` منتظر نمی‌مانیم:

```bash
make helm-deploy STAGE=dev HELM_ARGS="--set image.tag=1.0.0 --set config.modelUri=models:/churn/99 --timeout 30s"
```

انتظار (بعد از ۳۰ ثانیه): `Error: UPGRADE FAILED: ... context deadline exceeded` و `make: *** [helm-deploy] Error 1`. این خطا **مورد انتظار** است.

```bash
kubectl --context kind-mlops -n churn get pods
```

انتظار: یک پاد جدید `0/1 Running` (readiness probe رد می‌شود) **و** پاد قبلی `1/1 Running`.

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://churn.localhost:8080/ready
```

انتظار: `200`. کاربر خرابی را ندید. حالا revision سالم را پیدا کنید:

```bash
make helm-status
```

در جدول `helm history`، revisionی را بخوانید که `deployed` بود و پیش از خطا (revision با وضعیت `failed` نیست). بازگردانید:

```bash
make helm-rollback REV=<شماره‌ی revision سالم>
```

انتظار: `Rollback was a success! Happy Helming!` و در `make helm-status` یک revision تازه با توضیح `Rollback to ...`.

```bash
curl -s http://churn.localhost:8080/ready
```

> **زمان:** تا دقیقه‌ی ۴۵ باید اینجا باشید.

---

## گام ۴ — مانیتورینگ، drift و امتیاز آمادگی (۱۳ دقیقه)

```bash
make mon-status
```

اگر دو سطر `churn-api up` و `prometheus up` دیدید، مانیتورینگ جلسه‌ی ۱۳ روشن است. در غیر این صورت:

```bash
API_TAG=1.0.0 make mon-up
```

ترافیک بسازید و Grafana را باز کنید (`http://localhost:3001`، کاربر `admin`، رمز `mlops-lab`، داشبورد «Churn API: RED metrics»):

```bash
make load RPS=10 DURATION=30 BAD=0.1
```

انتظار: `status codes: {200: ..., 422: ...}` و روی داشبورد Rate بالا می‌رود.

گزارش drift (بار اول چند ده ثانیه طول می‌کشد، چون Evidently نصب می‌شود):

```bash
make drift
```

انتظار: جدول ستون‌ها و `3 of 7 columns drifted` و فایل `reports/drift-v1-v2.html`.

### امتیاز آمادگی

فایل‌های جلسه را کپی کنید:

```bash
S=~/mlops-lab/s14
```

```bash
cp $S/scripts/readiness_check.sh scripts/ && cp $S/Makefile .
```

فهرست آیتم‌ها را در `$S/PRODUCTION-READINESS.md` یک بار بخوانید، بعد:

```bash
TAG=1.0.0 scripts/readiness_check.sh
```

انتظار: ۶ گروه A تا F، خط‌های `PASS` سبز و `FAIL` قرمز با «چطور درست کنم» زیر هر کدام. حدود ۴۰ ثانیه طول می‌کشد (pytest و Trivy). سه امتیاز CI (`O2`) بدون رمز Gitea `SKIP` می‌شود؛ برای سنجش آن:

```bash
export GITEA_USER=student; read -rs -p "Gitea password: " GITEA_PASSWORD; export GITEA_PASSWORD; echo
```

```bash
TAG=1.0.0 scripts/readiness_check.sh
```

(به جای `student` نام کاربری Gitea خودتان را بگذارید. رمز تایپ‌شده نمایش داده نمی‌شود و جایی ذخیره نمی‌شود. بعد از پایان `unset GITEA_PASSWORD` بزنید.)

حالت انتظار در این لحظه: حدود ۸۰ امتیاز؛ آیتم‌های `X1` تا `X3` و `X5` قرمزند چون هنوز سند ندارید. این‌ها گام بعد است.

> **زمان:** تا دقیقه‌ی ۵۸ باید اینجا باشید.

---

## گام ۵ — سندها، نسخه‌ی v1.0.0 و Demo (۱۷ دقیقه)

### سندها (۷ دقیقه)

روی یک شاخه‌ی تازه کار کنید:

```bash
git switch -c release/v1.0.0
```

```bash
cp $S/RUNBOOK.md $S/DEMO.md . && cp $S/README.project.md README.md
```

سه فایل را با ویرایشگر باز کنید و:

1. هر جای‌نگهدار را (علامت کوچک‌تر، کلمه‌ی FILL با حروف بزرگ، دو نقطه و یک راهنما) با متن و عدد **خودتان** عوض کنید. عددها را از خروجی‌های همین جلسه بردارید (metrics، امتیاز، p95 از Grafana).
2. بند راهنمای اول هر فایل (که می‌گوید «این بند را پاک کنید») را پاک کنید.
3. در `RUNBOOK.md` یک حادثه‌ی واقعی که امروز دیدید (مثلاً خطای مدل ناموجود) را در جدول `Known incidents` بنویسید.

تا چیزی از جای‌نگهدار مانده، این دستور خطوط باقی‌مانده را نشان می‌دهد:

```bash
grep -n 'FILL' README.md RUNBOOK.md DEMO.md
```

انتظار: هیچ خروجی. بعد دوباره امتیاز:

```bash
make readiness TAG=1.0.0
```

انتظار: `X1` و `X2` و `X3` سبز، امتیاز ۹۰ یا بیشتر (بدون بررسی CI حدود ۹۷؛ با CI سبز ۱۰۰).

### <bdi dir="rtl">commit، merge و tag (۳ دقیقه)</bdi>

```bash
git add README.md RUNBOOK.md DEMO.md scripts/readiness_check.sh Makefile
```

```bash
git commit -m "docs: README, RUNBOOK, DEMO and readiness check (capstone)"
```

```bash
git push -u origin release/v1.0.0
```

در Gitea یک Pull Request بسازید. اجرای `ci` را ببینید، Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v1.0.0 -m "Capstone: churn mini production"
```

```bash
git push origin v1.0.0
```

### <bdi dir="rtl">Demo و دفاع (۷ دقیقه برای هر زوج؛ بقیه تماشا)</bdi>

دو نفر دو نفر. هر نفر: Demo پنج‌دقیقه‌ای از روی `DEMO.md` (مدرس زمان می‌گیرد)، بعد سؤال از فهرست `STORYTELLING.md` بخش ۳ (مدرس یا هم‌گروه). ده دقیقه قبل `make demo-check` بزنید. ترتیب: نفر اول Demo، نفر دوم سؤال می‌کند؛ بعد برعکس.

---

## بررسی پایان کار

```bash
TAG=1.0.0 ~/mlops-lab/scripts/verify.sh s14
```

انتظار: ۷ بررسی، همه `[PASS]`. اگر خطی `[FAIL]` شد، زیر آن می‌گوید چه چیزی کم است. خروجی را برای مدرس بفرستید.

## معیار پایان کار

- [ ] `~/work/churn-clean` از clone تمیز ساخته شد و بدون دست زدن به پروژه‌ی قدیمی اجرا شد
- [ ] می‌دانید چرا بعد از clone نه `.env` داشتید نه `config.local` و چرا این درست است
- [ ] `dvc repro --force` همان `roc_auc` و `f1` پروژه‌ی قدیمی را داد
- [ ] می‌دانید چرا `dvc repro` بعد از `dvc pull` چیزی اجرا نکرد
- [ ] image `churn-api:1.0.0` ساخته، scan و push شد، و release روی cluster از همین image است
- [ ] خرابی (مدل ناموجود) را دیدید، سرویس هنوز ۲۰۰ می‌داد، و با `helm rollback` برگشتید
- [ ] `scripts/readiness_check.sh` را اجرا کردید و می‌توانید بگویید کدام آیتم‌ها چرا قرمز بودند
- [ ] `README.md`، `RUNBOOK.md` و `DEMO.md` پر شده‌اند (بدون جای‌نگهدار)
- [ ] امتیاز آمادگی ۸۰ یا بیشتر است
- [ ] `TAG=1.0.0 ~/mlops-lab/scripts/verify.sh s14` همه‌ی بررسی‌ها را `PASS` داد
- [ ] tag `v1.0.0` روی `main` است و push شده
- [ ] Demo پنج‌دقیقه‌ای را ارائه کردید و به یک سؤال دفاع جواب دادید

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `git clone` خطای `Could not resolve host` یا `Connection refused` | Gitea خاموش است | `cd ~/mlops-lab/compose && docker compose up -d gitea` |
| `dvc pull`: `403` یا `Unable to locate credentials` | `.dvc/config.local` نیست (هیچ‌وقت در clone نمی‌آید) | `set -a; source .env; set +a`، بعد دو دستور `dvc remote modify --local` گام ۱ |
| `dvc pull`: `Could not connect to the endpoint URL` | SeaweedFS خاموش است یا پورت `8333` را برنامه‌ی دیگری دارد | `docker compose ps` در `~/mlops-lab/compose`؛ `docker compose up -d seaweedfs` |
| `uv sync` کند است یا `error sending request` | PyPI در دسترس نیست | اینترنت یا mirror مدرس (`UV_DEFAULT_INDEX`) |
| `dvc repro` می‌گوید `up to date` و run تازه‌ای در MLflow نیست | رفتار درست DVC بعد از `dvc pull` | `uv run dvc repro --force` |
| `dvc repro --force`: `MLflow server not reachable` | MLflow خاموش است یا `.env` را `source` نکرده‌اید | `set -a; source .env; set +a`؛ `curl http://localhost:5050/health` |
| `make image`: `failed to resolve source metadata for docker.io/docker/dockerfile:1` | خط اول Dockerfile از Docker Hub می‌پرسد و اینترنت قطع است | خط `# syntax=docker/dockerfile:1` را پاک و commit کنید (جلسه‌ی ۱۳) |
| `make scan` قرمز با یک شناسه‌ی `CVE` | کتابخانه‌ی قدیمی مانده است؛ ستون `Fixed Version` راه‌حل را نشان می‌دهد | ستون `Library` و `Fixed Version` را بخوانید؛ `uv lock --upgrade-package NAME` و سپس commit. مرحله‌ی scan را حذف نکنید |
| `make scan`: `unable to initialize the DB` یا `--skip-db-update ... no such file` | پایگاه Trivy در `~/.cache/trivy` نیست | `~/mlops-lab/scripts/install-from-bundle.sh` یا از مدرس بپرسید |
| `docker run`: `Conflict. The container name "/churn-clean-api" is already in use` | اجرای قبلی هنوز هست | `docker rm -f churn-clean-api` |
| `curl localhost:8011/ready` برابر `503` | `@champion` نیست یا MLflow خاموش بود | `make models`؛ MLflow را بالا بیاورید و container را با `docker rm -f` پاک و دوباره اجرا کنید |
| `helm-deploy`: `no matches for kind` یا `Kubernetes cluster unreachable` | cluster خاموش است | `docker start kind-registry mlops-control-plane`؛ `kubectl --context kind-mlops get nodes` |
| پاد `ImagePullBackOff` | `make push TAG=1.0.0` را نزده‌اید یا registry خاموش است | `curl localhost:5001/v2/churn-api/tags/list` باید `1.0.0` را نشان دهد؛ `docker start kind-registry` |
| `curl churn.localhost:8080` جواب نمی‌دهد | Traefik یا Ingress نیست، یا پورت ۸۰۸۰ برنامه‌ی دیگری دارد | `kubectl --context kind-mlops -n traefik get pods`؛ `make ingress-up`؛ در Linux/WSL قدیمی: `curl -H 'Host: churn.localhost' localhost:8080/ready` |
| `helm-deploy` با مدل ناموجود زمان زیادی صبر می‌کند | `--timeout 30s` را در `HELM_ARGS` ننوشته‌اید (پیش‌فرض ۱۲۰ ثانیه) | `HELM_ARGS="... --timeout 30s"` |
| `helm rollback`: `release has no deployed ...` یا شماره‌ی revision نمی‌شناسد | شماره‌ی نادرست | `make helm-status` و یک revision با وضعیت `deployed` یا `superseded` که قبل از خرابی بود |
| `make mon-up`: `port is already allocated` | مانیتورینگ جلسه‌ی ۱۳ هنوز روشن است | `make mon-status`؛ اگر هر دو `up` هستند، دوباره بالا آوردن لازم نیست |
| `make drift`: `No module named 'evidently'` | با `python` مستقیم اجرا کرده‌اید | حتماً `make drift` |
| `readiness_check.sh`: آیتم‌های سرویس و cluster قرمزند | آدرس‌ها پیش‌فرض نیستند یا سرویس خاموش است | `make demo-check`؛ متغیرهای `SERVICE_URL`، `KCTX` را مطابق راهنمای بالای اسکریپت بدهید |
| `readiness_check.sh`: `S5` قرمز با «image or trivy missing» | `TAG` را نداده‌اید (پیش‌فرض `0.7.0`) | `TAG=1.0.0 scripts/readiness_check.sh` |
| `readiness_check.sh`: `R6` قرمز (`dvc status` تمیز نیست) | `dvc pull` یا `dvc repro` را نزده‌اید | `uv run dvc pull` و `uv run dvc status` |
| `readiness_check.sh`: `X4` قرمز | فایلی تغییر کرده و commit نشده | `git status`؛ commit کنید (گام ۵) |
| `verify.sh s14`: `s14_tag` قرمز | tag را روی شاخه‌ی `release/...` زده‌اید یا PR را Merge نکرده‌اید | بعد از Merge: `git switch main && git pull`، سپس tag را بزنید و `git push origin v1.0.0` |
| Windows: دستورها خطای عجیب می‌دهند | از PowerShell استفاده می‌کنید | همه‌ی دستورها را داخل WSL Ubuntu بزنید |

**نگه‌دارید:** سرویس‌ها را بعد از جلسه هم پاک نکنید. `~/work/churn-clean` پروژه‌ی تحویلی شماست؛ پوشه‌ی `~/work/churn-mlops` را هر وقت خواستید نگه دارید یا بایگانی کنید. برای صرفه‌جویی در حافظه می‌توانید مانیتورینگ را خاموش کنید:

```bash
make mon-down
```

## بعد از دوره

- تکلیف اختیاری: ویدئوی ۳ دقیقه‌ای Demo ([HOMEWORK.md](HOMEWORK.md)).
- دوره‌ی دوم (MLOps Production and Enterprise On-Prem): همین پروژه با ذخیره‌ساز واقعی AWS S3، Kubernetes سخت‌شده، GitOps با ArgoCD، KServe، canary، HITL و policy. اسلایدهای جلسه نقشه‌ی کامل و جدول نگاشت On-Prem و Cloud را دارند.

</div>
