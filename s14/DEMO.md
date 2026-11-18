<div dir="rtl">

# Demo: churn-mlops (۵ دقیقه)

این فایل متن Demo شماست. آن را در ریشه‌ی پروژه با نام `DEMO.md` بگذارید و هر جای‌نگهدار (علامت کوچک‌تر، کلمه‌ی FILL با حروف بزرگ، دو نقطه و یک راهنما) را با عدد و جمله‌ی خودتان عوض کنید. `scripts/readiness_check.sh` (آیتم X3) تا وقتی یک جای‌نگهدار در فایل مانده باشد این آیتم را قبول نمی‌کند. این بند را هم در پایان پاک کنید.

قاعده‌ی طلایی: **هر ادعا یک دستور یا یک نمودار دارد.** عددی که روی صفحه نمی‌بینید را نگویید. راهنمای کامل storytelling، جمله‌های رزومه و سؤال‌های دفاع در `~/mlops-lab/s14/STORYTELLING.md` است.

## پیش از شروع (۱۰ دقیقه قبل از Demo)

```bash
cd ~/work/churn-mlops && make demo-check
```

سه ترمینال یا سه tab آماده کنید: (۱) دستورها، (۲) مرورگر با Grafana (`http://localhost:3001`) و گزارش drift، (۳) یک tab ثابت با دستور «خراب کردن» که هنوز اجرا نشده. اندازه‌ی فونت ترمینال را بزرگ کنید. پوشه‌ی پروژه را از قبل `cd` کنید.

```bash
set -a; source .env; set +a
```

## 0:00 تا 0:30 — مسئله و نتیجه

بگویید: <FILL: یک جمله — مثلاً «پیش‌بینی ریزش مشتری، از داده‌ی نسخه‌دار تا یک API پایش‌شده روی Kubernetes»>.
نمودار معماری `README.md` را نشان دهید و عدد اصلی را بگویید: <FILL: roc_auc و f1 از `dvc metrics show`>.

## 0:30 تا 1:15 — داده و pipeline بازتولیدپذیر

```bash
git describe --tags && uv run dvc dag
```

```bash
uv run dvc metrics show
```

بگویید: <FILL: چرا این عددها روی هر ماشین یکی می‌شوند؟ (داده با md5 در DVC، پارامتر در params.yaml، کد در Git)>.

## 1:15 تا 2:00 — چرخه‌ی عمر مدل

```bash
make models
```

نشان دهید ستون `gate` و alias `@champion` را. بگویید: <FILL: چرا ارتقا به champion خودکار نیست؟>.

## 2:00 تا 3:00 — سرویس زنده و پایش

```bash
curl -s http://churn.localhost:8080/ready
```

```bash
curl -s -X POST http://churn.localhost:8080/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

در tab دوم Grafana را باز کنید و در ترمینال ترافیک بسازید (۲۰ ثانیه):

```bash
make load API_URL=http://localhost:8003 RPS=10 DURATION=20 BAD=0.1
```

به سه نمودار اشاره کنید: Rate، Errors، Duration. بگویید: <FILL: p95 تأخیر شما چند میلی‌ثانیه است و از کجا دیدید؟>.

## 3:00 تا 4:00 — خرابی و بازگشت

در tab سوم این دستور را بزنید (حدود ۳۰ ثانیه صبر می‌کند و شکست می‌خورد؛ در همان مدت حرف بزنید):

```bash
make helm-deploy STAGE=dev HELM_ARGS="--set config.modelUri=models:/churn/99 --timeout 30s"
```

در ترمینال اول نشان دهید پاد جدید `0/1` است ولی سرویس هنوز جواب می‌دهد:

```bash
kubectl --context kind-mlops -n churn get pods
```

```bash
curl -s http://churn.localhost:8080/ready
```

حالا بازگشت (شماره‌ی revision خوب را از `make helm-status` بخوانید):

```bash
make helm-status
```

```bash
make helm-rollback REV=<FILL: شماره‌ی revision سالم>
```

بگویید: <FILL: چرا کاربر خرابی را ندید؟ (readiness probe)>.

## 4:00 تا 4:40 — drift و امتیاز آمادگی

گزارش `reports/drift-v1-v2.html` را در مرورگر نشان دهید: ستون‌های drift‌دار <FILL: نام ستون‌ها>.

```bash
QUICK=1 scripts/readiness_check.sh | tail -8
```

امتیاز شما: <FILL: score>/100. یک مورد که ناقص است و قصد دارید درست کنید: <FILL: item>.

## 4:40 تا 5:00 — جمع‌بندی

سه جمله: چه ساختید، چه یاد گرفتید، قدم بعدی چیست (<FILL: مثلاً canary یا GitOps>). بعد: «سؤال؟»

## اگر چیزی خراب شد (برنامه‌ی پشتیبان)

- نمودار خالی بود: `make load DURATION=30` را دوباره بزنید و بازه‌ی Grafana را `Last 5 minutes` کنید.
- `churn.localhost` جواب نداد: به جای آن `curl -H 'Host: churn.localhost' http://localhost:8080/ready` را بزنید.
- Rollback گیر کرد: `make helm-status` را نشان دهید و بگویید چه می‌کنید؛ دفاع از فرایند ارزشمندتر از Demo بی‌نقص است.
- زمان کم آمد: بخش drift را حذف کنید، نه بخش خرابی و بازگشت را.

</div>
