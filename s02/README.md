<div dir="rtl">

# آزمایشگاه جلسه‌ی ۲ — Git برای ML و کیفیت کد

در این آزمایشگاه پروژه‌ی جلسه‌ی ۱ را روی یک سرور Git (Gitea) می‌گذارید، با شاخه و Pull Request کار می‌کنید، آزمون می‌نویسید و نگهبان‌هایی نصب می‌کنید که جلوی commit شدن کد نامرتب و رمز را می‌گیرند.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. [آماده‌سازی جلسه‌ی ۲](SETUP.md) را انجام داده باشید (Docker و ابزارها).
2. پروژه‌ی جلسه‌ی ۱ سالم باشد:

```bash
cd ~/work/churn-mlops && make train
```

انتظار: `{'roc_auc': 0.802, 'f1': 0.5969}`

3. مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s02
```

همه‌ی دستورهای بعد در پوشه‌ی `~/work/churn-mlops` اجرا می‌شوند، مگر جایی که گفته شده. اگر ترمینال را بستید و دوباره باز کردید، خط `K=...` را دوباره بزنید.

فایل‌ها را با VS Code (`code .`) یا `nano` ویرایش کنید، نه TextEdit یا Notepad.

## نتیجه‌ی نهایی

- مخزن `churn-mlops` روی Gitea، با دو Pull Request ادغام‌شده و tag نسخه‌ی `v0.1.0`
- چهار آزمون سبز
- <bdi dir="rtl">hookهایی که فایل env و کلید داخل کد را رد می‌کنند</bdi>

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `pyproject-snippet.toml` | انتهای `pyproject.toml` | تنظیمات ruff و pytest |
| `test_data.py` | `tests/` | دو آزمون برای داده |
| `test_train.py` | `tests/` | یک آزمون برای مدل؛ آزمون چهارم را خودتان می‌نویسید |
| `.pre-commit-config.yaml` | ریشه‌ی پروژه | hookهای آفلاین (با `ls -a` دیده می‌شود) |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

در اسلایدها مسیر فایل‌های آماده `~/mlops-lab/starter/s02` نوشته شده است؛ در این مخزن همان فایل‌ها در `~/mlops-lab/s02` هستند.

---

## گام ۰ — تکلیف جلسه‌ی ۱ روی یک شاخه (۱۰ دقیقه)

اگر تکلیف را قبلاً انجام داده و commit کرده‌اید، به گام ۱ بروید.

> **اول این را بررسی کنید.** فایل‌های پوشه‌ی `s01` مخزن دوره بلوک `eval` را از قبل دارند. اگر پروژه‌تان را با کپی همان فایل‌ها ساخته‌اید، تغییری برای این گام نمی‌ماند و اضافه کردن دوباره‌ی `eval:` فایل YAML را خراب می‌کند (کلید تکراری).
>
> ```bash
> grep -n "eval" configs/params.yaml
> ```
>
> اگر خروجی خط `eval:` را نشان داد:
>
> 1. گام ۰ را کامل رد کنید. فقط مطمئن شوید همه‌چیز روی `main` commit شده است (خروجی `git status --short` خالی باشد).
> 2. در گام ۱ دستور push شاخه‌ی `feature/eval-threshold` را اجرا نکنید؛ همان push شاخه‌ی `main` کافی است.
> 3. در گام ۲ بخش Pull Request را رد کنید و فقط tag را بزنید. اولین Pull Request خود را در گام ۶ می‌سازید.
>
> اگر خروجی خالی بود، گام ۰ را مثل زیر انجام دهید.

```bash
git switch -c feature/eval-threshold
```

به **انتهای** `configs/params.yaml` این دو خط را اضافه کنید (خط دوم دو فاصله تورفتگی دارد، نه Tab):

```yaml
eval:
  threshold: 0.5
```

در `src/churn/train.py` عبارت `proba > 0.5` را به این تغییر دهید:

```python
proba > p["eval"]["threshold"]
```

```bash
make train
```

انتظار: همان عددهای قبل.

```bash
git status --short
```

```bash
git add configs/params.yaml src/churn/train.py
```

```bash
git commit -m "feat: read decision threshold from eval config"
```

```bash
git log --oneline --all
```

باید **دو** commit ببینید. اگر یکی دیدید، commit انجام نشده است؛ خروجی `git commit` را بخوانید.

## گام ۱ — Gitea و اولین push (۱۵ دقیقه)

<bdi dir="rtl">Gitea را بالا بیاورید:</bdi>

```bash
cd ~/mlops-lab/compose && cp -n .env.example .env; docker compose up -d gitea
```

```bash
docker compose ps
```

سرویس `gitea` باید `Up` باشد.

یک کاربر بسازید. به‌جای `YOUR_PASSWORD` رمز دلخواه خودتان را بگذارید و آن را به خاطر بسپارید:

```bash
docker exec -u git gitea gitea admin user create --username student --password 'YOUR_PASSWORD' --email student@lab.local --admin --must-change-password=false
```

در مرورگر به `http://localhost:3000` بروید و با `student` وارد شوید. علامت + بالا سمت راست، New Repository، نام `churn-mlops`، **بدون هیچ تیکی** (بدون README و gitignore)، Create Repository.

مخزن را به سرور وصل کنید و بفرستید:

```bash
cd ~/work/churn-mlops && git remote add origin http://localhost:3000/student/churn-mlops.git
```

```bash
git push -u origin main
```

نام کاربری `student` و رمز خودتان را می‌پرسد. هنگام تایپ رمز چیزی روی صفحه دیده نمی‌شود؛ طبیعی است.

```bash
git push -u origin feature/eval-threshold
```

صفحه‌ی مخزن را در مرورگر تازه کنید؛ فایل‌ها باید دیده شوند.

## گام ۲ — اولین Pull Request و tag (۱۰ دقیقه)

در Gitea: زبانه‌ی Pull Requests، New Pull Request، مقصد `main` و مبدأ `feature/eval-threshold`. توضیح:

```
Moves the decision threshold from code to configs/params.yaml (eval block).
Metrics unchanged: roc_auc 0.802, f1 0.5969.
```

<bdi dir="rtl">Create Pull Request. زبانه‌ی Files Changed را ببینید، بعد Create merge commit و Delete Branch.</bdi>

لپ‌تاپ را هم‌گام کنید:

```bash
git switch main && git pull
```

```bash
git branch -d feature/eval-threshold
```

نسخه را برچسب بزنید:

```bash
git tag -a v0.1.0 -m "Baseline: logistic regression, ROC-AUC 0.80"
```

```bash
git push origin v0.1.0
```

## گام ۳ — ابزارهای کیفیت: ruff (۱۰ دقیقه)

```bash
git switch -c feature/quality-gates
```

```bash
cd ~/work/churn-mlops && uv add --dev ruff pytest pre-commit
```

```bash
cat $K/pyproject-snippet.toml >> pyproject.toml
```

```bash
uv run ruff check .
```

```bash
uv run ruff format --check .
```

دستور دوم فایل‌هایی را که قالب نامرتب دارند فهرست می‌کند. درستشان کنید و ببینید چه عوض شد:

```bash
uv run ruff format .
```

```bash
git diff --stat
```

```bash
git add . && git commit -m "chore: add ruff and pytest config"
```

## گام ۴ — آزمون‌ها (۱۵ دقیقه)

```bash
mkdir -p tests && cp $K/test_*.py tests/
```

```bash
uv run pytest -q
```

انتظار: `3 passed`. اجرای اول ممکن است تا یک دقیقه طول بکشد.

**آزمون چهارم را خودتان بنویسید.** انتهای `tests/test_train.py` یک توضیح TODO هست. آزمون باید بگوید: اگر مشتری‌ای با نوع قراردادی بیاید که مدل هرگز ندیده (مثلاً `"weekly"`)، `predict` نباید از کار بیفتد.

راهنما:
- با `X, y = _xy()` داده بگیرید.
- مدل را مثل آزمون بالایی بسازید و آموزش دهید.
- با `X.head(1).assign(contract="weekly")` یک مشتری بسازید.
- <bdi dir="rtl">`model.predict(...)` را روی او صدا بزنید و بررسی کنید خروجی یک عضو دارد.</bdi>

```bash
uv run pytest -q
```

انتظار: `4 passed`.

```bash
uv run ruff check --fix . && uv run ruff format .
```

```bash
git add . && git commit -m "test: add data and model unit tests"
```

## گام ۵ — pre-commit و دو آزمایش (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && cp $K/.pre-commit-config.yaml .
```

```bash
uv run pre-commit install --hook-type pre-commit --hook-type pre-push
```

**آزمایش ۱ — فایل env.** چون `.env` در `.gitignore` است، برای آزمایش با `-f` اضافه‌اش می‌کنیم:

```bash
echo "DEBUG=1" > .env && git add -f .env
```

```bash
git commit -m "chore: add env"
```

انتظار: commit رد می‌شود با `block .env files....Failed`. پاک‌سازی:

```bash
git restore --staged .env && rm .env
```

**آزمایش ۲ — کلید داخل کد:**

```bash
echo 'S3_SECRET_ACCESS_KEY = "abcd1234efgh5678ijkl"' > src/churn/settings.py
```

```bash
git add src/churn/settings.py && git commit -m "feat: s3 settings"
```

انتظار: `block hard-coded secrets....Failed` با نام فایل و شماره‌ی خط. پاک‌سازی:

```bash
git restore --staged src/churn/settings.py && rm src/churn/settings.py
```

حالا فایل تنظیم hookها را commit کنید (این بار باید همه `Passed` شوند):

```bash
git add .pre-commit-config.yaml && git commit -m "chore: add pre-commit hooks"
```

## گام ۶ — Pull Request دوم (۵ دقیقه)

```bash
git push -u origin feature/quality-gates
```

قبل از push، hook مرحله‌ی pre-push آزمون‌ها را اجرا می‌کند. در Gitea یک Pull Request از `feature/quality-gates` به `main` بسازید، بازبینی و Merge کنید. بعد:

```bash
git switch main && git pull
```

```bash
git branch -d feature/quality-gates
```

---

## بررسی پایان کار

```bash
~/mlops-lab/scripts/verify.sh s02
```

انتظار:

```
[PASS] remote origin -> Gitea, branch main is pushed
[PASS] ruff check + ruff format are clean
[PASS] pytest: at least 4 tests passed
[PASS] pre-commit hooks installed (pre-commit + pre-push) and config tracked
[PASS] tag v0.1.0 exists locally and on Gitea
s02: 5/5 checks passed
```

خروجی این دستور را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `nothing to commit, working tree clean` | فایلی تغییر نکرده یا ذخیره نشده | فایل را ذخیره کنید؛ `git status --short` |
| `found character '\t' that cannot start any token` | در فایل YAML کاراکتر Tab هست | خط را پاک و با فاصله (Space) دوباره تایپ کنید؛ `cat -et configs/params.yaml` کاراکترهای پنهان را نشان می‌دهد |
| `KeyError: 'eval'` یا `KeyError: 'threshold'` | بخش `eval` ذخیره نشده یا با حرف بزرگ نوشته شده | باید دقیقاً `eval:` و `threshold:` با حروف کوچک باشد |
| `build_model() got an unexpected keyword argument 'threshold'` | `threshold` زیر بخش `train` رفته | آن را زیر بخش جدای `eval` بگذارید |
| تغییر روی `main` هم دیده می‌شود | تغییر هنوز commit نشده؛ تغییر commit‌نشده با شما بین شاخه‌ها جابه‌جا می‌شود | روی شاخه‌ی خودتان commit کنید |
| `Authentication failed` هنگام push | نام کاربری یا رمز اشتباه | نام کاربری `student` است، نه ایمیل. بازنشانی رمز: `docker exec -u git gitea gitea admin user change-password --username student --password 'NEW' --must-change-password=false` |
| push بدون پرسیدن رمز رد می‌شود (مک) | رمز غلط در keychain ذخیره شده | `printf "protocol=http\nhost=localhost:3000\n" \| git credential-osxkeychain erase` |
| `Push to create is not enabled for users` (خطای 403) | مخزن هنوز روی Gitea ساخته نشده، یا نامش با آدرس remote یکی نیست | مخزن `churn-mlops` را در مرورگر بسازید (بدون هیچ تیکی)؛ `git remote -v` را با آدرس صفحه‌ی مخزن مقایسه کنید |
| `No such file or directory` هنگام `cd ~/mlops-lab/...` | مخزن دوره را جای دیگری clone کرده‌اید | به‌جای `~/mlops-lab` مسیر مخزن خودتان را بگذارید |
| `no configuration file provided: not found` | `docker compose` بیرون از پوشه‌ی `compose` اجرا شده | اول `cd` به پوشه‌ی `compose` مخزن دوره |
| push «گیر کرده» | منتظر رمز است، یا Ctrl+Z زده‌اید | رمز را تایپ کنید و Enter؛ برای لغو Ctrl+C (نه Ctrl+Z) |
| `src refspec ... does not match any` | شاخه‌ای با این نام روی لپ‌تاپ نیست | `git branch` را ببینید؛ شاخه را بسازید و commit کنید |
| `port is already allocated` برای ۳۰۰۰ | برنامه‌ی دیگری روی این پورت است | آن برنامه را ببندید |
| `error: No pyproject.toml found in current directory` | دستور در پوشه‌ی دوره (`~/mlops-lab/s02`) اجرا شده، نه در پروژه | اول `cd ~/work/churn-mlops`؛ اگر در `~/mlops-lab/s02` فایل `pyproject.toml` ساخته شد، آن را با `uv.lock` و `.venv` پاک کنید |
| `Failed to spawn: pre-commit` | `pre-commit` در این پوشه نصب نیست (پوشه‌ی اشتباه یا گام ۴ انجام نشده) | در `~/work/churn-mlops` اول `uv add --dev ruff pytest pre-commit` و بعد `install` |
| `No .pre-commit-config.yaml file was found` | روی شاخه‌ای هستید که این فایل را ندارد؛ hookها روی همه‌ی شاخه‌ها فعال‌اند | `git merge main` در آن شاخه |
| ruff فایل را عوض کرد و commit رد شد | طبیعی است؛ ruff اصلاح کرده | دوباره `git add` و `git commit` |
| `paths are ignored: .env` | `.env` در gitignore است | برای آزمایش: `git add -f .env` |
| `ModuleNotFoundError: make_dataset` در pytest | بخش `[tool.pytest.ini_options]` به `pyproject.toml` اضافه نشده | گام ۳ را دوباره ببینید |

<bdi dir="rtl">`git commit --no-verify` راه‌حل هیچ‌کدام از این‌ها نیست؛ پیام خطا را بخوانید و علت را رفع کنید.</bdi>

</div>
