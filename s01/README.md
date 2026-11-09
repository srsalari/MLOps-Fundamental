<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱ — اولین مدل Churn

در این آزمایشگاه یک پروژه‌ی ML مرتب می‌سازید، داده‌ی مصنوعی تولید می‌کنید و اولین مدل (خط پایه) را آموزش می‌دهید.

زمان تقریبی: ۳۰ تا ۴۵ دقیقه.

## نتیجه‌ی نهایی

در پایان باید این خروجی را ببینید:

```
{'roc_auc': 0.802, 'f1': 0.5969}
```

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `make_dataset.py` | `scripts/` | ساخت داده‌ی مصنوعی مشتری‌ها |
| `train.py` | `src/churn/` | آموزش و ارزیابی مدل |
| `params.yaml` | `configs/` | تنظیمات (hyperparameterها) |
| `Makefile` | ریشه‌ی پروژه | دستورهای کوتاه `make data` و `make train` |
| `gitignore` | ریشه‌ی پروژه، با نام `.gitignore` | فایل‌هایی که نباید در Git بروند |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

## پیش‌نیازها

- <bdi dir="rtl">`git`</bdi>
- <bdi dir="rtl">`make`</bdi>
- [`uv`](https://docs.astral.sh/uv/) (پایتون ۳٫۱۲ را خودش نصب می‌کند)
- اینترنت، برای دریافت کتابخانه‌ها در گام ۲

بررسی:

```bash
git --version && make --version | head -1 && uv --version
```

### macOS

<bdi dir="rtl">`git` و `make` با Xcode Command Line Tools می‌آیند:</bdi>

```bash
xcode-select --install
```

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Linux (Ubuntu / Debian)

```bash
sudo apt update && sudo apt install -y git make curl
```

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Windows

از WSL2 استفاده کنید. در PowerShell با دسترسی Administrator:

```powershell
wsl --install -d Ubuntu
```

سیستم را ری‌استارت کنید و برنامه‌ی Ubuntu را از منوی Start باز کنید (یا در PowerShell بنویسید `wsl`).

> **مهم:** از این‌جا به بعد هیچ دستوری را در PowerShell اجرا نکنید. دستورهای بخش Linux و همه‌ی گام‌های بعد فقط داخل پنجره‌ی Ubuntu کار می‌کنند.
>
> راه تشخیص: اگر ابتدای خط `PS C:\...>` می‌بینید در PowerShell هستید؛ در Ubuntu چیزی شبیه `name@pc:~$` می‌بینید.

برای اطمینان از نصب بودن Ubuntu، در PowerShell:

```powershell
wsl -l -v
```

پس از نصب `uv` ترمینال را ببندید و دوباره باز کنید.

## گام‌ها

### گام ۰ — دریافت این مخزن

```bash
git clone https://github.com/srsalari/MLOps-Fundamental.git ~/mlops-lab
```

اگر قبلاً clone کرده‌اید، فقط آن را به‌روز کنید: `git -C ~/mlops-lab pull`

مسیر این پوشه را در یک متغیر نگه دارید:

```bash
K=~/mlops-lab/s01
```

```bash
ls $K
```

باید پنج فایل جدول بالا و همین `README.md` را ببینید.

### گام ۱ — ساخت پروژه

```bash
mkdir -p ~/work/churn-mlops && cd ~/work/churn-mlops
```

```bash
git init -b main
```

```bash
uv init --package --name churn --python 3.12
```

### گام ۲ — نصب کتابخانه‌ها

```bash
uv add scikit-learn pandas pyyaml
```

این دستور محیط `.venv` را می‌سازد و نسخه‌ی دقیق کتابخانه‌ها را در `uv.lock` ثبت می‌کند.

### گام ۳ — کپی فایل‌های آماده

```bash
mkdir -p scripts configs
cp $K/make_dataset.py scripts/
cp $K/train.py src/churn/
cp $K/params.yaml configs/
cp $K/Makefile .
cp $K/gitignore .gitignore
```

### گام ۴ — ساخت داده

```bash
make data
```

خروجی مورد انتظار:

```
wrote 5000 rows to data/raw/churn.csv (churn rate 36.1%)
```

### گام ۵ — آموزش مدل

```bash
make train
```

خروجی مورد انتظار:

```
{'roc_auc': 0.802, 'f1': 0.5969}
```

- <bdi dir="rtl">**ROC-AUC:** توان مدل در جدا کردن مشتری رفته از مشتری مانده. عدد ۰٫۵ یعنی شانسی و ۱ یعنی بی‌نقص.</bdi>
- <bdi dir="rtl">**F1:** ترکیب دقت و پوشش پیش‌بینی‌های «می‌رود».</bdi>

### گام ۶ — آزمون تکرارپذیری و commit

دوباره اجرا کنید؛ عددها باید دقیقاً همان باشند:

```bash
make train
```

اگر Git نام و ایمیل شما را نمی‌شناسد، یک بار تنظیم کنید:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

```bash
git add . && git commit -m "feat: project skeleton + baseline training"
```

```bash
git status --short && git log --oneline
```

<bdi dir="rtl">`git status` باید خالی باشد و `git log` یک commit نشان دهد.</bdi>

## بررسی پایان کار

- [ ] `make data` عدد ۵۰۰۰ ردیف و نرخ ریزش ۳۶٫۱٪ را نشان می‌دهد.
- [ ] `make train` دو بار پشت سر هم همان `roc_auc` و `f1` را می‌دهد.
- [ ] فایل‌های `models/model.joblib` و `metrics.json` ساخته شده‌اند.
- [ ] `git status --short` خالی است.
- [ ] پوشه‌های `data/` و `models/` در commit نیستند.

## ساختار پروژه پس از آزمایشگاه

```
churn-mlops/
├── src/churn/train.py
├── scripts/make_dataset.py
├── configs/params.yaml
├── data/raw/churn.csv        (not in Git)
├── models/model.joblib       (not in Git)
├── metrics.json              (not in Git)
├── Makefile
├── pyproject.toml
├── uv.lock
└── README.md
```

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `The token '&&' is not a valid statement separator` | دستور Linux در PowerShell اجرا شده | پنجره‌ی Ubuntu را باز کنید (`wsl`) و دستور را آن‌جا اجرا کنید |
| `command not found: uv` | ترمینال پس از نصب دوباره باز نشده | ترمینال را ببندید و باز کنید |
| `command not found: make` | `make` نصب نیست | بخش پیش‌نیازها را ببینید |
| `Makefile:4: *** missing separator` | خط دستور با فاصله شروع شده، نه با TAB | فایل `Makefile` را دوباره از این پوشه کپی کنید |
| `ModuleNotFoundError: No module named 'churn'` | `train.py` در جای اشتباه است | باید در `src/churn/train.py` باشد |
| `FileNotFoundError: data/raw/churn.csv` | داده ساخته نشده | اول `make data` را اجرا کنید |
| عددها با خروجی مورد انتظار فرق دارند | `params.yaml` یا نسخه‌ی کتابخانه‌ها تغییر کرده | `params.yaml` را دوباره کپی کنید |
| کندی شدید در Windows | پروژه زیر `/mnt/c` ساخته شده | پروژه را در `~/work` داخل WSL بسازید |

## تمرین

در `train.py` آستانه‌ی تصمیم داخل کد نوشته شده است (`proba > 0.5`).

1. آن را به `configs/params.yaml` ببرید و کد را طوری تغییر دهید که از آن‌جا بخواند.
2. <bdi dir="rtl">`make train` را اجرا کنید؛ عددها نباید تغییر کنند.</bdi>
3. آستانه را ۰٫۳ کنید. کدام عدد عوض می‌شود و کدام نه؟ چرا؟

</div>
