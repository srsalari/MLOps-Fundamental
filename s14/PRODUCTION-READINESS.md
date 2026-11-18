<div dir="rtl">

# چک‌لیست آمادگی Production (۱۰۰ امتیاز)

این چک‌لیست می‌گوید پروژه‌ی Churn شما چقدر به «سرویسی که می‌شود به آن تکیه کرد» نزدیک است. ۳۴ آیتم دارد، هر آیتم به یک جلسه‌ی دوره وصل است، و هر آیتم را با **یک دستور** می‌شود سنجید. اسکریپت `scripts/readiness_check.sh` همین دستورها را خودکار اجرا می‌کند و امتیاز می‌دهد:

```bash
cd ~/work/churn-clean && scripts/readiness_check.sh
```

## قواعد امتیاز

| نتیجه | معنی |
|---|---|
| `PASS` | آیتم کامل برقرار است؛ همه‌ی امتیازش را می‌گیرید |
| `FAIL` | برقرار نیست؛ صفر امتیاز. زیر آن خط «چطور درست کنم» چاپ می‌شود |
| `SKIP` | سنجیده نشد (مثلاً رمز Gitea ندادید یا `QUICK=1` زدید). امتیاز ندارد و جدا در پایان گزارش می‌آید |

نمره‌ی کل و معنی آن:

| امتیاز | وضعیت |
|---|---|
| ۹۰ تا ۱۰۰ | آماده‌ی production کوچک (mini) |
| ۸۰ تا ۸۹ | آماده‌ی Demo؛ باقی آیتم‌ها را وقتی توانستید درست کنید |
| ۶۰ تا ۷۹ | تقریباً؛ پیش از Demo آیتم‌های قرمز را درست کنید |
| زیر ۶۰ | هنوز نه؛ از آیتم‌های پرامتیاز شروع کنید |

اسکریپت هرگز چیزی را عوض نمی‌کند (فقط می‌خواند) و سؤال نمی‌پرسد. آدرس‌ها را از متغیرهای محیطی می‌گیرد (پیش‌فرض‌ها مقدار کلاس‌اند): `SERVICE_URL`، `PROM_URL`، `GRAFANA_URL`، `REGISTRY_URL`، `KCTX`، `NS`، `RELEASE`، `IMAGE`، `TAG`. برای آیتم CI نام کاربری و رمز Gitea را با `GITEA_USER` و `GITEA_PASSWORD` بدهید؛ بدون آن آن آیتم `SKIP` می‌شود. با `QUICK=1` دو آیتم کند (pytest و Trivy) رد می‌شوند.

## A. بازتولیدپذیری (۲۰ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| R1 | ۳ | ۱ و ۲ | `uv.lock` در Git است و همه‌ی وابستگی‌ها با `==` قفل شده‌اند | `grep -c '==' pyproject.toml` |
| R2 | ۳ | ۳ | `.env` در Git نیست، `.env.example` هست، رمز S3 در هیچ فایل و commit نیست | `git ls-files .env .env.example` |
| R3 | ۲ | ۲ | `ruff check` و `ruff format --check` تمیز | `make lint` |
| R4 | ۴ | ۲ و ۵ و ۸ | pytest: حداقل ۲۰ تست سبز و هیچ شکستی | `make test` |
| R5 | ۳ | ۴ | داده فقط pointer DVC است، remote از نوع S3، tagهای `data-v1` و `data-v2` | `uv run dvc remote list && git tag -l 'data-v*'` |
| R6 | ۳ | ۵ | `dvc.yaml` سه stage دارد، `dvc.lock` در Git است، `dvc status` تمیز | `uv run dvc status` |
| R7 | ۲ | ۲ | حداقل ۵ tag نسخه (`v0.x.0`) و همه روی origin | `git ls-remote --tags origin 'v*'` |

## B. چرخه‌ی عمر مدل (۱۲ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| M1 | ۴ | ۶ | MLflow جواب می‌دهد و experiment شماره‌ی ۱ حداقل یک run دارد | `curl -s $MLFLOW_TRACKING_URI/health && make runs` |
| M2 | ۴ | ۷ | مدل ثبت‌شده‌ی `churn` alias به نام `@champion` دارد | `make models` |
| M3 | ۴ | ۷ | نسخه‌ی champion برچسب `gate=passed` و `data_md5` دارد (دروازه عبور داده و داده‌ی آن مشخص است) | `make models` (ستون gate) |

## C. سرویس و image (۱۸ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| S1 | ۴ | ۸ | سرویس: `/ready` جواب می‌دهد، `/predict` معتبر جواب می‌دهد، ورودی بد `422` می‌گیرد | `curl -i http://churn.localhost:8080/ready` |
| S2 | ۲ | ۸ و ۱۳ | `/metrics` شمارنده‌ی `http_requests_total` را نشان می‌دهد | `curl -s http://churn.localhost:8080/metrics \| grep http_requests_total` |
| S3 | ۳ | ۹ | Dockerfile: دو مرحله، `USER` غیر root، `HEALTHCHECK` | `grep -E '^(FROM\|USER\|HEALTHCHECK)' Dockerfile` |
| S4 | ۱ | ۹ | `.dockerignore` فایل `.env` و پوشه‌ی `.git` را کنار می‌گذارد | `cat .dockerignore` |
| S5 | ۴ | ۹ | Trivy: هیچ آسیب‌پذیری HIGH یا CRITICAL قابل‌رفع در image نیست | `make scan TAG=1.0.0` |
| S6 | ۲ | ۹ | registry محلی tag دارد | `curl -s localhost:5001/v2/churn-api/tags/list` |
| S7 | ۲ | ۸ | `tests/test_api.py` حداقل ۳ تست دارد | `grep -c '^def test_' tests/test_api.py` |

## D. استقرار (۲۰ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| D1 | ۲ | ۱۰ | playbook و inventory Ansible در Git هستند و `--syntax-check` را رد می‌کنند | `cd deploy && uv run ansible-playbook --syntax-check deploy.yml` |
| D2 | ۴ | ۱۱ و ۱۲ | chart (برای dev و prod) این‌ها را می‌سازد: `readinessProbe`، `livenessProbe`، `resources` با requests و limits | `helm template x chart/churn-api -f chart/churn-api/values-prod.yaml \| grep -E 'Probe\|limits\|requests'` |
| D3 | ۱ | ۱۲ | `helm lint` با values-dev و values-prod | `helm lint chart/churn-api -f chart/churn-api/values-prod.yaml` |
| D4 | ۲ | ۱۲ | `values-prod.yaml`: حداقل ۲ replica و مدل **قفل‌شده** (`models:/churn/N`، نه `@champion`) | `grep -E 'replicaCount\|modelUri' chart/churn-api/values-prod.yaml` |
| D5 | ۴ | ۱۱ و ۱۲ | release Helm در namespace مقصد `deployed` است و همه‌ی replicaها ready | `make helm-status` |
| D6 | ۴ | ۱۲ | Traefik بر اساس host مسیر می‌دهد: `churn.localhost` برابر ۲۰۰ و `other.localhost` برابر ۴۰۴ | `curl -s -o /dev/null -w '%{http_code}\n' http://other.localhost:8080/ready` |
| D7 | ۳ | ۱۰ و ۱۲ | Makefile هدف‌های بازگشت دارد (`rollback`، `helm-rollback`) | `grep -E '^(rollback\|helm-rollback):' Makefile` |

## E. خودکارسازی و پایش (۱۴ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| O1 | ۳ | ۱۳ | سه workflow (`ci`، `ml-ci`، `retrain`)؛ `ci` سه مرحله‌ی lint و test و scan دارد؛ هیچ `uses:` نیست | `ls .gitea/workflows && grep -c 'uses:' .gitea/workflows/*.yaml` |
| O2 | ۳ | ۱۳ | در Gitea یک اجرای `ci` روی `main` موفق بوده است | Gitea، Actions |
| O3 | ۳ | ۱۳ | Prometheus سرویس را scrape می‌کند (target برابر `up`) و rule به نام `ChurnApiDown` بار شده | `make mon-status` |
| O4 | ۲ | ۱۳ | داشبورد «Churn API: RED metrics» در Grafana هست | `http://localhost:3001` |
| O5 | ۳ | ۱۳ | Evidently قفل شده و `reports/drift-v1-v2.html` ساخته شده | `make drift` |

## F. مستندات و تحویل (۱۶ امتیاز)

| کد | امتیاز | جلسه | چه چیزی باید برقرار باشد | بررسی دستی |
|---|---|---|---|---|
| X1 | ۴ | ۱۴ | `README.md`: حداقل ۲۰ خط، بخش Quick start و Architecture، بدون `TODO` و `<FILL` | `grep -n 'FILL' README.md` |
| X2 | ۵ | ۱۴ | `RUNBOOK.md`: بخش‌های Start و Stop و Restart و Logs و Rollback و Health، با دستور، بدون `<FILL` | `grep -n '^## ' RUNBOOK.md` |
| X3 | ۳ | ۱۴ | `DEMO.md`: حداقل ۵ بخش زمان‌دار (مثل `0:30`)، بدون `<FILL` | `grep -n '^## ' DEMO.md` |
| X4 | ۲ | ۱۴ | روی `main` هستید و فایل ردیابی‌شده‌ای تغییر نکرده | `git status` |
| X5 | ۲ | ۱۴ | tag `v1.0.0` هم محلی هم روی origin | `git ls-remote --tags origin v1.0.0` |

## چطور از آن استفاده کنیم

۱. ابتدا اسکریپت را اجرا کنید و **آیتم‌های قرمز را به ترتیب امتیاز** بخوانید.
۲. آیتم‌های سند (X1 تا X3) سریع‌ترین امتیاز را می‌دهند: ۱۲ امتیاز با سه فایل.
۳. هر چه درست کردید، دوباره اسکریپت را بزنید (`make readiness`). امتیاز نهایی را در `README.md` و `DEMO.md` بنویسید.
۴. صادق باشید: امتیاز را با حذف آیتم بالا نبرید. اگر آیتمی برای پروژه‌ی شما معنی ندارد، در Demo بگویید چرا و امتیاز را همان بگذارید.

یادآوری: ۱۰۰ امتیاز یعنی «برای یک mini production آماده است»، نه «برای production واقعی». نبودن Alertmanager، autoscaling، canary، backup و امنیت شبکه عمداً در این چک‌لیست نیست؛ آن‌ها موضوع دوره‌ی دوم‌اند.

</div>
