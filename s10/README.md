<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱۰ — استقرار روی VM با Ansible (Infrastructure as Code)

در جلسه‌ی ۹ سرویس را در یک image گذاشتید. ولی خیلی از سازمان‌ها هنوز سرویس‌هایشان را روی **ماشین مجازی (VM)** یا سرور معمولی اجرا می‌کنند، بدون Kubernetes. در این آزمایشگاه همان سرویس churn را روی یک VM اوبونتو مستقر می‌کنید، به شکلی که یک مهندس واقعی انجام می‌دهد: برنامه به‌صورت یک **سرویس systemd** اجرا می‌شود (اگر خراب شد خودش دوباره بالا می‌آید)، جلوی آن **Nginx** به‌عنوان reverse proxy می‌ایستد، لاگ‌ها **چرخش (rotate)** می‌شوند، و کل کار نه با دست، بلکه با یک **playbook Ansible** انجام می‌شود. یعنی زیرساخت به‌صورت کد در Git است (**IaC**)، قابل تکرار، و دوبار اجرا کردنش خرابی نمی‌سازد. در پایان یک `RUNBOOK.md` می‌نویسید و یک rollback واقعی را تمرین می‌کنید.

زمان تقریبی: ۷۵ دقیقه.

یک نکته‌ی صادقانه: «VM» ما در این آزمایشگاه در واقع یک **container** است که مثل VM رفتار می‌کند (اوبونتو ۲۴٫۰۴ با systemd و SSH). دلیلش این است که روی macOS، Linux و WSL فقط با Docker یکسان کار می‌کند و چیز اضافه نصب نمی‌شود. تفاوت واقعی با VM را در گام ۲ خودتان می‌بینید. کسی که بخواهد VM واقعی داشته باشد می‌تواند از **Multipass** استفاده کند (در جلسه‌ی ۱۱ با آن آشنا می‌شوید)؛ playbook همان می‌ماند و فقط آدرس در inventory عوض می‌شود.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۹ سالم باشد: `main` شامل tag `v0.7.0` است، مدل `churn` در Registry دارای `@champion` است و سرویس‌های قبلی (SeaweedFS و MLflow) را پاک نکرده‌اید (`docker compose down -v` نزده باشید).
2. بررسی آمادگی را اجرا کنید:

```bash
~/mlops-lab/s10/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s10
```

در این جلسه همه‌ی کار در یک ترمینال انجام می‌شود (به جز لحظه‌هایی که داخل VM هستید و آن را خودتان می‌بینید). اگر ترمینال را بستید، خط `K=...` را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell؛ Docker هم داخل همان Ubuntu نصب است (جلسه‌ی ۲) و باید روشن باشد. دانشجوهای macOS: Docker Desktop (یا Colima) باید در حال اجرا باشد.

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| VM (ماشین مجازی) | یک کامپیوتر نرم‌افزاری با سیستم‌عامل و هسته‌ی (kernel) خودش. در بانک‌ها، شرکت‌های بزرگ و سیستم‌های قدیمی هنوز رایج است |
| container در برابر VM | container هسته را با میزبان شریک است و سبک‌تر است؛ VM هسته‌ی خودش را دارد. «VM» تمرینی ما یک container است |
| systemd | مدیر سرویس‌های لینوکس: برنامه را روشن می‌کند، بعد از reboot بالا می‌آورد، اگر مُرد دوباره روشن می‌کند |
| unit | فایل توضیح یک سرویس برای systemd (`churn-api.service`) |
| reverse proxy | برنامه‌ای (اینجا Nginx) که درخواست‌های بیرون را می‌گیرد و به برنامه‌ی پشتش می‌فرستد؛ API ما فقط به خود VM گوش می‌دهد |
| log rotation | لاگ را هر روز بایگانی و فشرده می‌کنیم تا دیسک پر نشود (ابزار `logrotate`) |
| IaC | زیرساخت و تنظیم سرور را به‌صورت فایل متنی در Git نگه می‌داریم، نه با کلیک و دستور پراکنده |
| Ansible | ابزاری که از طریق SSH روی سرورها کار انجام می‌دهد؛ روی خود سرور برنامه‌ی ویژه نمی‌خواهد (فقط پایتون) |
| inventory | فهرست سرورهایی که Ansible مدیریت می‌کند (`inventory.ini`) |
| playbook | فایل YAML که می‌گوید سرور باید چه وضعیتی داشته باشد (`deploy.yml`) |
| task و module | task یک قدم از playbook است و هر task یک module را صدا می‌زند (مثلاً `apt`، `copy`، `template`) |
| handler | taskی که فقط وقتی اجرا می‌شود که taskی دیگر چیزی را «تغییر داده» باشد (مثل restart بعد از عوض شدن فایل تنظیم) |
| template | فایل تنظیم با جاهای خالی (`{{ model_uri }}`) که Ansible پر می‌کند (قالب Jinja2) |
| idempotency | اجرای دوباره‌ی playbook وقتی چیزی عوض نشده، هیچ تغییری نمی‌دهد (`changed=0`) |
| `--check` و `--diff` | اجرای آزمایشی: بگو چه چیزی عوض می‌شد و تفاوت فایل‌ها را نشان بده، بدون اینکه واقعاً چیزی عوض شود |
| Terraform | ابزار IaC برای **ساختن** زیرساخت (خود VM، شبکه، دیسک در ابر). Ansible برای **تنظیم** داخل ماشین است. در این دوره فقط معرفی است و آزمایشگاه ندارد |
| runbook | سند کوتاه برای کسی که ساعت سه شب پای سرویس می‌نشیند: چطور بررسی کنم، چطور restart کنم، چطور به عقب برگردم، با چه کسی تماس بگیرم |

## نتیجه‌ی نهایی

- یک VM تمرینی (`mlops-vm`) که با `make vm-up` بالا می‌آید و با SSH روی پورت 2223 در دسترس است
- سرویس `churn-api` روی VM به‌صورت سرویس systemd، با Nginx جلوی آن (روی لپ‌تاپ: `http://localhost:8090`)
- پوشه‌ی `deploy/` با inventory، playbook و قالب‌ها که با یک دستور (`make deploy`) همه‌چیز را می‌سازد
- فایل `RUNBOOK.md` در ریشه‌ی پروژه
- توانایی rollback سریع به نسخه‌ی قبلی مدل (`make rollback VERSION=1`)
- کد در Git با tag نسخه‌ی `v0.8.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `vm/Dockerfile` | همین‌جا می‌ماند (با `make vm-image` ساخته می‌شود) | ساخت image «VM» تمرینی: اوبونتو ۲۴٫۰۴ با systemd و SSH و Nginx |
| `deploy/ansible.cfg` | پوشه‌ی `deploy/` در پروژه | تنظیم Ansible: کاربر، کلید SSH، مسیر پایتون |
| `deploy/inventory.ini` | پوشه‌ی `deploy/` در پروژه | فهرست سرورها (فقط `mlops-vm`) |
| `deploy/deploy.yml` | پوشه‌ی `deploy/` در پروژه | playbook استقرار |
| `deploy/templates/*.j2` | پوشه‌ی `deploy/templates/` در پروژه | چهار قالب: فایل تنظیم، unit سرویس، logrotate، سایت Nginx |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۹) | هدف‌های تازه‌ی `vm-image`، `vm-up`، `vm-ssh`، `release`، `deploy`، `rollback` |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

توضیح خط‌به‌خط فایل‌های این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — وضعیت شروع و VM تمرینی (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git describe --tags
```

انتظار: `v0.7.0` (اگر تکلیف جلسه‌ی ۹ را merge کرده‌اید چیزی مثل `v0.7.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

```bash
git switch -c feature/vm-deploy
```

سرویس‌های جلسه‌های قبل را روشن کنید. VM ما روی شبکه‌ی `mlops-lab` قرار می‌گیرد و باید MLflow را آنجا ببیند:

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

```bash
cd ~/work/churn-mlops
```

<bdi dir="rtl">Makefile جلسه‌ی ۹ را با Makefile این جلسه عوض کنید (هدف‌های قبلی همه در آن هستند):</bdi>

```bash
cp $K/Makefile .
```

حالا image «VM» را بسازید. مدرس ممکن است image آماده را در بسته‌ی آفلاین داده باشد؛ در آن صورت این گام را رد کنید و `docker images mlops/practice-vm` را ببینید. اگر نبود:

```bash
make vm-image
```

انتظار: ساخت بین ۵۰ تا ۹۰ ثانیه طول می‌کشد (بسته‌های اوبونتو را از اینترنت می‌گیرد) و بدون خطا تمام می‌شود. اندازه‌ی image را ببینید:

```bash
docker images mlops/practice-vm:24.04
```

انتظار: یک ردیف برای `mlops/practice-vm` با tag `24.04` و اندازه‌ی حدود 282MB.

حالا VM را روشن کنید:

```bash
make vm-up
```

انتظار: یک شناسه‌ی بلند (container) چاپ می‌شود و دستور بدون خطا تمام می‌شود. این هدف چند کار می‌کند: container را با گزینه‌ی `--privileged` اجرا می‌کند (systemd به آن نیاز دارد)، یک کلید SSH به نام `~/.ssh/mlops_vm` می‌سازد (فقط بار اول)، کلید عمومی را داخل VM می‌گذارد، و کلید قدیمی VM را از `known_hosts` پاک می‌کند. اگر VM تازه ساخته شده باشد، خطی مثل `# Host [127.0.0.1]:2223 found: line 1` هم ممکن است ببینید؛ عادی است.

چند ثانیه صبر کنید (systemd حدود ۴ ثانیه برای بالا آمدن وقت می‌خواهد) و وارد VM شوید:

```bash
make vm-ssh
```

انتظار: بار اول یک هشدار مثل `Warning: Permanently added '[127.0.0.1]:2223' (ED25519) to the list of known hosts.` و بعد یک prompt مثل `ubuntu@mlops-vm:~$`. **از این لحظه داخل VM هستید.** اگر `Permission denied (publickey)` گرفتید، جدول عیب‌یابی را ببینید.

داخل VM این سه دستور را بزنید:

```bash
hostname
```

انتظار: `mlops-vm`

```bash
whoami
```

انتظار: `ubuntu`

```bash
systemctl is-system-running
```

انتظار: `running` (اگر `starting` بود چند ثانیه بعد دوباره بزنید)

از VM بیرون بیایید:

```bash
exit
```

حالا prompt دوباره مال لپ‌تاپ شماست. VM در پس‌زمینه روشن می‌ماند.

## گام ۲ — Ansible: inventory و اولین فرمان‌ها (۱۵ دقیقه)

<bdi dir="rtl">Ansible را به‌عنوان کتابخانه‌ی توسعه به پروژه اضافه کنید (روی لپ‌تاپ نصب می‌شود؛ داخل VM چیزی نصب نمی‌شود):</bdi>

```bash
uv add --dev ansible-core==2.21.4
```

انتظار: حدود ۵ ثانیه، و `uv.lock` و `pyproject.toml` عوض می‌شوند.

```bash
uv run ansible --version
```

انتظار: خط اول `ansible [core 2.21.4]`

پوشه‌ی `deploy/` را کپی کنید:

```bash
cp -r $K/deploy .
```

دو فایل کوچک را باز کنید و بخوانید. اولی فهرست سرورهاست:

```bash
cat deploy/inventory.ini
```

انتظار: یک گروه `[api]` و یک خط `mlops-vm ansible_host=127.0.0.1 ansible_port=2223`. یعنی «سرور `mlops-vm` در گروه `api` است و از طریق پورت 2223 لپ‌تاپ به آن SSH می‌زنیم».

```bash
cat deploy/ansible.cfg
```

انتظار: کاربر `ubuntu`، کلید `~/.ssh/mlops_vm` و مسیر پایتون `/usr/bin/python3`. (توضیح در [CODE.md](CODE.md).)

از این به بعد دستورهای Ansible را از داخل پوشه‌ی `deploy` اجرا می‌کنیم، چون `ansible.cfg` را از پوشه‌ی جاری می‌خواند:

```bash
cd deploy
```

اولین فرمان **ad-hoc**: «آیا می‌توانی به همه‌ی سرورها وصل شوی؟»

```bash
uv run ansible all -m ping
```

انتظار:

```
mlops-vm | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

این `ping` از نوع ICMP نیست؛ module است و یعنی «SSH کار کرد و پایتون روی سرور هست».

یک دستور روی گروه `api` اجرا کنید:

```bash
uv run ansible api -a "uptime"
```

انتظار (اعداد شما فرق دارند):

```
mlops-vm | CHANGED | rc=0 >>
 14:52:02 up 1 day, 12:01,  0 user,  load average: 0.23, 0.49, 0.42
```

**به عدد uptime دقت کنید.** در نمونه‌ی ما «بیش از یک روز» بود، در حالی که VM همین الان ساخته شده! دلیل: این VM یک container است و **هسته را با میزبان شریک است**؛ `uptime` زمان روشن بودن Docker host را نشان می‌دهد، نه خود VM. در یک VM واقعی (Multipass یا VirtualBox) عدد چند دقیقه می‌بود. این یکی از تفاوت‌های container و VM است. برای کار ما (systemd، SSH، Nginx، Ansible) فرقی نمی‌کند.

ساختار inventory را ببینید:

```bash
uv run ansible-inventory --graph
```

انتظار:

```
@all:
  |--@ungrouped:
  |--@api:
  |  |--mlops-vm
```

حالا playbook را بدون اجرا بررسی کنید. اول درستی نوشتار YAML:

```bash
uv run ansible-playbook deploy.yml --syntax-check
```

انتظار: `playbook: deploy.yml`

```bash
uv run ansible-playbook deploy.yml --list-tasks
```

انتظار: عنوان `play #1 (api): Deploy the churn API` و زیر آن فهرست ۱۶ task. این فهرست «نقشه‌ی» کار است؛ هنوز چیزی روی VM تغییر نکرده.

به ریشه‌ی پروژه برگردید:

```bash
cd ..
```

## گام ۳ — اولین استقرار (۲۰ دقیقه)

### <bdi dir="rtl">playbook چه می‌کند؟</bdi>

فایل `deploy/deploy.yml` به ترتیب این کارها را روی VM می‌کند (توضیح کامل هر task در [CODE.md](CODE.md)):

| مرحله | کار |
| --- | --- |
| بسته‌ها | مطمئن می‌شود `python3-venv`، `nginx` و `logrotate` نصب‌اند |
| کاربر و پوشه‌ها | کاربر سیستمی `churn` (بدون shell ورود) و پوشه‌های `/opt/churn-api`، `/var/log/churn-api`، `/etc/churn-api` |
| کتابخانه‌ها | فایل `requirements.txt` را کپی و در یک virtualenv روی VM نصب می‌کند |
| برنامه | فایل wheel برنامه را کپی و نصب می‌کند (فقط اگر عوض شده باشد) |
| تنظیم‌ها | چهار قالب را پر می‌کند: فایل تنظیم (آدرس MLflow و مدل)، unit سرویس systemd، logrotate، سایت Nginx |
| سرویس‌ها | `churn-api` و `nginx` را فعال (`enabled`) و روشن (`started`) می‌کند |
| handlerها | اگر تنظیمی عوض شده باشد، `churn-api` را restart و Nginx را reload می‌کند |
| آخر کار | تا ۲۰ بار هر ۳ ثانیه `http://127.0.0.1/ready` را از داخل VM صدا می‌زند تا جواب ۲۰۰ بگیرد |

دو فایل `dist/` و `deploy/requirements.txt` را `make release` می‌سازد و نباید وارد Git شوند. به `.gitignore` اضافه کنید:

```bash
printf 'dist/\ndeploy/requirements.txt\n' >> .gitignore
```

حالا همه‌چیز را با یک دستور مستقر کنید:

```bash
make deploy
```

این هدف اول `make release` را می‌زند (ساخت wheel برنامه با `uv build` و فهرست قفل‌شده‌ی کتابخانه‌ها با `uv export`)، بعد playbook را اجرا می‌کند.

انتظار: **بار اول حدود ۲ دقیقه و ۱۰ تا ۲۵ ثانیه طول می‌کشد**، چون task نصب کتابخانه‌ها حدود ۹۰ بسته را از PyPI **داخل VM** دانلود می‌کند؛ پس VM باید اینترنت (یا آینه‌ی PyPI دوره) داشته باشد. صبور باشید. اول `make release` چاپ می‌کند:

```
Successfully built dist/churn-0.1.0-py3-none-any.whl
```

(هشدار `build_system.requires = ["uv-build...` بی‌خطر است.) بعد task‌ها یکی‌یکی می‌آیند. در بار اول بیشترشان `changed` هستند. یک نکته‌ی مهم: در آخر یک خط قرمز مثل این می‌بینید و **خطا نیست**:

```
FAILED - RETRYING: [mlops-vm]: The API is ready behind Nginx (19 retries left).
```

یعنی API هنوز مدل را بار می‌کرد و Ansible ۳ ثانیه صبر کرد و دوباره پرسید. بعد از آن `ok` می‌آید و خط debug:

```
"msg": "ready: {'status': 'ready', 'model_version': '2'}"
```

(شماره‌ی `model_version` همان نسخه‌ی `@champion` شماست.) و در پایان **خلاصه‌ی اجرا**:

```
PLAY RECAP *********************************************************************
mlops-vm : ok=19 changed=15 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

عدد `failed=0` مهم‌ترین چیز است. `changed=15` یعنی ۱۵ task چیزی را تغییر دادند.

حالا از لپ‌تاپ، از بیرون VM (پورت 8090 که به پورت ۸۰ داخل VM یعنی Nginx می‌رسد) سرویس را صدا بزنید:

```bash
curl -s localhost:8090/health
```

انتظار: `{"status":"ok"}`

```bash
curl -s localhost:8090/ready
```

انتظار (شماره‌ی نسخه در سیستم شما فرق دارد): `{"status":"ready","model_version":"2"}`

```bash
curl -s -X POST localhost:8090/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار:

```
{"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"2"}
```

همان عدد ۰٫۹۰۳۲ جلسه‌های ۸ و ۹. حالا ثابت کنیم جواب را Nginx می‌دهد، نه خود uvicorn:

```bash
curl -sI localhost:8090/health | grep -i server
```

انتظار: `Server: nginx/1.24.0 (Ubuntu)`

پس مسیر درخواست این است: لپ‌تاپ (پورت 8090) به Docker به Nginx روی پورت ۸۰ به uvicorn روی `127.0.0.1:8000` داخل VM. پورت ۸۰۰۰ از بیرون VM اصلاً دیده نمی‌شود، و این عمدی است.

## گام ۴ — idempotency و Runbook (۱۵ دقیقه)

### اجرای دوباره

همان دستور را دوباره بزنید و چیزی را عوض نکرده‌اید:

```bash
make deploy
```

انتظار: این بار فقط حدود ۱۲ ثانیه طول می‌کشد و خلاصه چیزی مثل این است:

```
mlops-vm : ok=16 changed=0 unreachable=0 failed=0 skipped=1 rescued=0 ignored=0
```

<bdi dir="rtl">`changed=0` یعنی **idempotent**: Ansible وضعیت را بررسی کرد، دید همه‌چیز همان است که باید، و دست نزد. (`skipped=1` همان task نصب wheel است که چون wheel عوض نشده رد شد.) همین خاصیت باعث می‌شود بدون ترس هر وقت خواستید playbook را اجرا کنید.</bdi>

### کارهای روزمره‌ی یک اپراتور

وارد VM شوید:

```bash
make vm-ssh
```

از اینجا تا `exit` داخل VM هستید. وضعیت سرویس:

```bash
systemctl status churn-api --no-pager
```

انتظار (زمان و شماره‌ی PID فرق دارند):

```
● churn-api.service - Churn prediction API (uvicorn)
     Loaded: loaded (/etc/systemd/system/churn-api.service; enabled; preset: enabled)
     Active: active (running) since Fri 2026-10-23 14:47:44 UTC; 21s ago
   Main PID: 1073 (uvicorn)
      Tasks: 16 (limit: 9564)
     Memory: 166.1M (peak: 166.8M)
        CPU: 2.675s
     CGroup: /system.slice/churn-api.service
             └─1073 /opt/churn-api/venv/bin/python3 /opt/churn-api/venv/bin/uvicorn churn.api:app --host 127.0.0.1 --port 8000 --no-access-log
```

دو واژه‌ی مهم: `enabled` یعنی بعد از reboot خودش بالا می‌آید، و `active (running)` یعنی همین الان در حال اجراست.

```bash
systemctl is-active churn-api nginx
```

انتظار: دو خط `active` (یکی برای هر سرویس)

لاگ systemd:

```bash
journalctl -u churn-api --no-pager -n 5
```

انتظار (پنج خط آخر؛ اینجا فقط خطوط خود systemd هست، مثل `Started churn-api.service - Churn prediction API (uvicorn).`). لاگ خود برنامه جای دیگری است:

```bash
sudo tail -n 4 /var/log/churn-api/api.log
```

انتظار (چهار خط آخر؛ زمان‌ها و `run_id` فرق دارند). مثل این‌ها:

```
{"ts": "2026-10-23 14:42:43,615", "level": "INFO", "event": "model_loaded", "uri": "models:/churn@champion", "name": "churn", "version": "2", "run_id": "e2838a552ddc4327a27997abaae43deb", "seconds": 0.53}
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
{"ts": "...", "level": "INFO", "event": "request", "method": "GET", "path": "/ready", "status": 200, "ms": 1.0}
```

دلیل اینکه لاگ برنامه در `journalctl` نیست: در unit نوشته‌ایم `StandardOutput=append:/var/log/churn-api/api.log`، یعنی خروجی را مستقیم به فایل بفرست.

لاگ دسترسی Nginx (هر درخواست یک خط):

```bash
sudo tail -n 2 /var/log/nginx/churn-api.access.log
```

انتظار (نمونه): خط‌هایی مثل `"GET /ready HTTP/1.1" 200 38`. اگر روی یک VM تازه نگاه کنید ممکن است یک خط با کد `502` بالای کد `200` هم ببینید: وقتی Ansible هنوز API بالا نیامده بود پرسید.

فایل تنظیم سرویس را ببینید (مالک root، گروه churn، و فقط خواندنی برای بقیه):

```bash
ls -l /etc/churn-api/churn-api.env
```

انتظار: `-rw-r----- 1 root churn 255 ...` (روز و ساعت فرق دارد)

### <bdi dir="rtl">restart و ۵۰۲ کوتاه</bdi>

```bash
sudo systemctl restart churn-api
```

بلافاصله بعد از آن کد پاسخ را ببینید (قبل از اینکه چند ثانیه بگذرد):

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost/ready
```

انتظار: احتمالاً `502`. یعنی Nginx زنده است ولی برنامه‌ی پشتش هنوز بالا نیامده. بعد از حدود ۳ ثانیه دوباره بزنید:

```bash
curl -s -o /dev/null -w "%{http_code}\n" localhost/ready
```

انتظار: `200`. این ۵۰۲ کوتاه بعد از هر restart **عادی است**؛ فقط اگر بیشتر از چند ثانیه ماند به لاگ نگاه کنید.

### خراب شدن ناگهانی (crash test)

حالا برنامه را با زور بکشیم (`kill -9`) و ببینیم systemd چه می‌کند:

```bash
sudo kill -9 $(systemctl show churn-api -p MainPID --value)
```

بلافاصله:

```bash
systemctl is-active churn-api
```

انتظار: `activating` (یعنی systemd می‌خواهد دوباره بالا بیاورد؛ به خاطر `Restart=on-failure` و `RestartSec=3`)

```bash
systemctl show churn-api -p NRestarts
```

انتظار: `NRestarts=1`. اگر خیلی سریع زدید و هنوز `NRestarts=0` دیدید، چند ثانیه صبر کنید و دوباره بزنید (systemd پس از ۳ ثانیه، `RestartSec=3`، دوباره روشن می‌کند). حدود ۵ ثانیه بعد دوباره `curl -s localhost/ready` بزنید؛ باید `{"status":"ready",...}` بدهد. سرویس خودش را درمان کرد، بدون دخالت شما.

### چرخش لاگ

```bash
sudo logrotate -f /etc/logrotate.d/churn-api
```

(`-f` یعنی «همین الان، بدون منتظر ماندن تا فردا».) فایل‌ها را ببینید:

```bash
ls -l /var/log/churn-api/
```

انتظار: فایل `api.log` با اندازه‌ی **0** بایت و فایل تازه‌ی `api.log.1` که لاگ قبلی را دارد (اندازه‌ی شما فرق دارد؛ در نمونه 1067 بایت بود). فایل `.1` عمداً هنوز فشرده نیست (`delaycompress`)؛ دفعه‌ی بعدی فشرده می‌شود.

از VM بیرون بیایید:

```bash
exit
```

### نوشتن RUNBOOK.md

*<bdi dir="rtl">*Runbook** سندی است که اگر شما در دسترس نبودید، همکارتان با آن بتواند سرویس را نگه دارد. در ریشه‌ی پروژه فایل `RUNBOOK.md` را با ویرایشگر بسازید و این اسکلت را در آن بگذارید. جاهای `...` را **خودتان** پر کنید، با همان دستورهایی که همین الان زدید:</bdi>

```markdown
# Runbook: churn-api

## 1. Service overview
- What it does: ...
- Where it runs: VM `mlops-vm`, systemd unit `churn-api`, behind Nginx on port 80
- Depends on: MLflow at ... (what happens if it is down?)
- Files: app in ..., settings in ..., logs in ...

## 2. Start, stop, restart
- Start: ...
- Stop: ...
- Restart: ... (a short 502 right after is normal for about 3 s)

## 3. Check health
- Is it running? ...
- Is it ready (model loaded)? ...
- Which model version is served? ...

## 4. Logs
- App log: ...
- Nginx access log: ...
- systemd messages: ...
- Rotation: ...

## 5. Rollback
- Roll back the model to an older version: ...
- Roll forward again: ...
- How to verify: ...

## 6. Who to call
- Owner: ...
- Escalation: ...
```

بخش ۵ را بعد از گام ۵ پر کنید. سند را کوتاه نگه دارید: خواننده‌اش خسته و عجول است.

## گام ۵ — تمرین rollback و پایان (۱۵ دقیقه)

سناریو: نسخه‌ی ۲ مدل مشکل دارد و می‌خواهیم **سریع** به نسخه‌ی ۱ برگردیم. اول **اجرای آزمایشی** (dry run): ببینیم Ansible چه چیزی را عوض می‌کرد، بدون اینکه چیزی عوض شود.

```bash
cd deploy && uv run ansible-playbook deploy.yml --check --diff -e model_uri=models:/churn/1
```

انتظار: در میان خروجی، تفاوت فایل تنظیم را می‌بینید:

```
--- before: /etc/churn-api/churn-api.env
+++ after: .../churn-api.env.j2
-MODEL_URI=models:/churn@champion
+MODEL_URI=models:/churn/1
```

و خلاصه چیزی مثل `ok=15 changed=3 ... skipped=3`. این سه `changed`: فایل تنظیم، handler، و یک task نصب کتابخانه‌ها (`Libraries are installed ...`). آن task نصب کتابخانه‌ها در حالت `--check` **همیشه** `changed` نشان می‌دهد؛ این محدودیت خود Ansible است برای pip با فایل requirements (نمی‌تواند بدون نصب بفهمد چیزی لازم است یا نه). تغییر واقعی همان فایل تنظیم است. در این اجرا چیزی روی VM تغییر نکرد.

به ریشه برگردید:

```bash
cd ..
```

حالا rollback واقعی:

```bash
make rollback VERSION=1
```

انتظار: حدود ۱۵ ثانیه. دو task `changed` می‌شوند: فایل تنظیم و `RUNNING HANDLER [Restart churn-api]`. آخر کار `"msg": "ready: {'status': 'ready', 'model_version': '1'}"` و خلاصه‌ی `ok=17 changed=2 ... failed=0`.

```bash
curl -s localhost:8090/ready
```

انتظار: `{"status":"ready","model_version":"1"}`

سرویس اکنون نسخه‌ی ۱ را می‌دهد. برای «جلو رفتن» دوباره به `@champion` برگردید (همان `make deploy` معمولی):

```bash
make deploy
```

```bash
curl -s localhost:8090/ready
```

انتظار: `{"status":"ready","model_version":"2"}` (یا هر نسخه‌ای که `@champion` شماست)

حالا بخش ۵ فایل `RUNBOOK.md` را پر کنید، بعد commit:

```bash
git status --short
```

انتظار: `.gitignore`، `Makefile`، `pyproject.toml`، `uv.lock` با `M` و `deploy/` و `RUNBOOK.md` با `??`. (فایل‌های `dist/` و `deploy/requirements.txt` نباید دیده شوند.)

```bash
git add .gitignore Makefile deploy pyproject.toml uv.lock RUNBOOK.md && git commit -m "feat: deploy to a VM with Ansible (systemd + Nginx)"
```

```bash
git status --short
```

انتظار: خالی.

```bash
git push -u origin feature/vm-deploy
```

در Gitea (`http://localhost:3000`) برای شاخه‌ی `feature/vm-deploy` یک Pull Request بسازید و در توضیح بنویسید:

```
Deploy the inference API to a VM with Ansible.
Practice VM = Ubuntu 24.04 container with systemd and SSH (make vm-image, vm-up).
Playbook: venv + wheel, systemd unit (Restart=on-failure), Nginx reverse proxy, logrotate; idempotent.
Makefile: vm-image, vm-up, vm-ssh, release, deploy, rollback.
RUNBOOK.md: start/stop, health, logs, rollback.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.8.0 -m "Session 10: deploy on a VM with Ansible"
```

```bash
git push origin v0.8.0
```

---

## بررسی پایان کار

<bdi dir="rtl">VM و سرویس باید روشن باشند (`docker ps --filter name=mlops-vm` و `curl -s localhost:8090/ready`). MLflow هم باید روشن باشد. بعد:</bdi>

```bash
~/mlops-lab/scripts/verify.sh s10
```

انتظار: همه‌ی خط‌ها `[PASS]` باشند. اگر خطی `[FAIL]` شد، متن آن می‌گوید چه چیزی کم است؛ جدول عیب‌یابی را ببینید. خروجی را همراه با تکلیف برای مدرس بفرستید.

## معیار پایان کار

- [ ] شاخه‌ی `feature/vm-deploy` ساخته شد و با Pull Request وارد `main` شد
- [ ] `make vm-up` اجرا شد و با `make vm-ssh` توانستید وارد VM شوید (`hostname` برابر `mlops-vm`)
- [ ] `uv run ansible all -m ping` جواب `pong` داد
- [ ] `make deploy` بار اول بدون خطا تمام شد (`failed=0`) و بار دوم `changed=0` داد
- [ ] `curl localhost:8090/ready` جواب `ready` داد و هدر `Server` برابر `nginx` بود
- [ ] می‌توانید توضیح دهید چرا `uptime` در VM ما عدد زمان Docker host را نشان داد
- [ ] `kill -9` را زدید و دیدید سرویس خودش دوباره بالا آمد
- [ ] `make rollback VERSION=1` سرویس را روی نسخه‌ی ۱ برد و `make deploy` دوباره روی `@champion` آورد
- [ ] فایل `RUNBOOK.md` با همه‌ی شش بخش پر شد و commit شد
- [ ] tag `v0.8.0` روی `main` است و push شده
- [ ] `~/mlops-lab/scripts/verify.sh s10` همه‌ی بررسی‌ها را `PASS` داد

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| در `make deploy` task نصب کتابخانه‌ها خطای `Failed to import the required Python library (packaging)` می‌دهد | VM از یک image قدیمی ساخته شده که پکیج `python3-packaging` را ندارد | image را دوباره بسازید: `docker rm -f mlops-vm`، بعد `make vm-image` و `make vm-up` و دوباره `make deploy` (`vm/Dockerfile` فعلی این پکیج را دارد) |
| داخل VM: `systemctl status churn-api` می‌گوید `Failed to connect to bus: No such file or directory` | image قدیمی بدون پکیج `dbus` | همان راه‌حل بالا: image تازه بسازید و VM را دوباره بسازید. (با `sudo` کار می‌کند ولی در VM درست باید بدون `sudo` هم کار کند) |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` یا `Host key verification failed` | VM را دوباره ساخته‌اید و کلید میزبان جدید است | `make vm-up` کلید قدیمی را پاک می‌کند. دستی: `ssh-keygen -R "[127.0.0.1]:2223"` |
| `docker run`: `port is already allocated` یا `address already in use` برای 2223 یا 8090 | برنامه‌ی دیگری آن پورت را گرفته | `docker ps --filter publish=2223` و `docker ps --filter publish=8090` را ببینید. اگر خودِ `mlops-vm` قدیمی است: `docker rm -f mlops-vm`. اگر برنامه‌ی دیگری است آن را ببندید، یا پورت را بدهید: `make vm-up VM_SSH_PORT=2224 VM_HTTP_PORT=8091` (همان مقدار را برای `deploy` و `vm-ssh` هم بدهید) |
| `docker: Error response from daemon: Conflict. The container name "/mlops-vm" is already in use` | VM قبلی هنوز هست (حتی خاموش) | `docker rm -f mlops-vm` و دوباره `make vm-up`. **نام کامل** را بنویسید |
| `Permission denied (publickey)` | کلید داخل VM نرسیده | چهار خط `docker cp ... authorized_keys` و `docker exec ... chown` از هدف `vm-up` را دوباره اجرا کنید؛ ساده‌تر: `docker rm -f mlops-vm` و `make vm-up`. مطمئن شوید فایل `~/.ssh/mlops_vm` و `~/.ssh/mlops_vm.pub` هر دو هستند |
| `ansible all -m ping`: `UNREACHABLE` و `Connection refused` | VM هنوز بالا نیامده، یا از پوشه‌ی `deploy` اجرا نکرده‌اید (`ansible.cfg` خوانده نمی‌شود) | چند ثانیه صبر کنید؛ `docker ps --filter name=mlops-vm` باید `Up` باشد؛ مطمئن شوید `pwd` به `deploy` ختم می‌شود |
| `make deploy` در task «The API is ready behind Nginx» بعد از حدود ۱ دقیقه با `Status code was 503` شکست می‌خورد | MLflow خاموش است، یا `mlflow_uri` اشتباه است (داخل VM، `localhost` یعنی خود VM، نه لپ‌تاپ) | `curl -s http://localhost:5050/health` باید `OK` باشد. آدرس داخل شبکه باید `http://mlflow:5000` باشد (مقدار پیش‌فرض). علت دقیق را در لاگ ببینید: `make vm-ssh` و `sudo tail -n 20 /var/log/churn-api/api.log` (دنبال `model_load_failed`). بعد از رفع، دوباره `make deploy` |
| task نصب کتابخانه‌ها خیلی کند است یا خطای دانلود می‌دهد | VM به اینترنت یا آینه‌ی PyPI دوره دسترسی ندارد | بار اول طبیعی است ۲ دقیقه یا بیشتر طول بکشد. اگر قطع شد، اینترنت میزبان را بررسی کنید؛ در کلاس از مدرس بپرسید آینه‌ی دوره کدام است. دوباره `make deploy` بزنید (ادامه می‌دهد) |
| بعد از restart یا deploy چند ثانیه `502 Bad Gateway` | Nginx بالاست ولی برنامه هنوز مدل را بار می‌کند | عادی است؛ حدود ۳ ثانیه صبر کنید. اگر بیشتر ماند: `sudo tail -n 20 /var/log/churn-api/api.log` داخل VM |
| `make rollback` در همان ابتدا درباره‌ی فایل wheel (`dist/churn-*.whl`) خطا می‌دهد | wheel ساخته نشده، چون `rollback` خودش `release` را نمی‌زند | یک بار `make release` (یا `make deploy`) بزنید و دوباره `make rollback VERSION=1` |
| `make: *** No rule to make target 'vm-up'` | Makefile جلسه‌ی ۹ هنوز جایگزین نشده | در گام ۱ `cp $K/Makefile .` را بزنید |
| `Cannot connect to the Docker daemon` | Docker روشن نیست | macOS: Docker Desktop (یا `colima start`) را روشن کنید. Ubuntu و WSL: `sudo systemctl start docker` |
| Windows: دستورها خطای عجیب یا `ssh` پیدا نمی‌شود | از PowerShell استفاده می‌کنید | همه‌ی دستورها را داخل WSL Ubuntu بزنید؛ Docker هم باید داخل همان Ubuntu نصب باشد (جلسه‌ی ۲)، نه Docker Desktop ویندوز با PowerShell |
| `ansible-playbook`: `command not found` | Ansible به پروژه اضافه نشده، یا بدون `uv run` زده‌اید | در ریشه‌ی پروژه `uv add --dev ansible-core==2.21.4` (گام ۲) و دستورها را با `uv run` بزنید |
| `warning: build_system.requires = ["uv-build...` | نسخه‌ی `uv` با ابزار ساخت پروژه فرق دارد | بی‌خطر |
| `verify.sh s10` در یکی از بررسی‌ها `FAIL` می‌دهد | VM یا سرویس خاموش است، یا commit یا tag کم است | متن همان خط را بخوانید؛ `docker ps --filter name=mlops-vm` و `curl -s localhost:8090/ready` را بررسی کنید و گام مربوط را کامل کنید |
| tag `v0.8.0` روی commit قدیمی است (پیش از merge زده شده) | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.8.0 && git push origin :refs/tags/v0.8.0`، بعد روی `main` به‌روز دوباره tag و push |

سرویس‌های آزمایشگاه (SeaweedFS، MLflow، registry محلی) را نگه دارید و `docker compose down -v` نزنید. VM را هم نگه دارید: `docker rm -f mlops-vm` را فقط در پایان دوره یا وقتی مدرس گفت بزنید (حدود 1GB فضا می‌گیرد). تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

</div>
