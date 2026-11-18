<div dir="rtl">

# توضیح کد جلسه‌ی ۱۰

در جلسه‌ی ۹ سرویس را در یک image گذاشتیم. در این جلسه همان سرویس را روی یک **VM** مستقر می‌کنیم، ولی نه با دست: یک **playbook Ansible** همه‌ی کارها را انجام می‌دهد. کد پایتون برنامه تغییر نمی‌کند؛ این جلسه فایل‌های «استقرار» دارد.

فایل‌های این جلسه:

- فایل `vm/Dockerfile`: image «VM» تمرینی (اوبونتو با systemd و SSH).
- فایل `deploy/ansible.cfg`: تنظیم‌های Ansible برای این پوشه.
- فایل `deploy/inventory.ini`: فهرست سرورها.
- فایل `deploy/deploy.yml`: playbook استقرار. مهم‌ترین فایل این جلسه است.
- چهار قالب در `deploy/templates/`: فایل تنظیم، unit سرویس، logrotate و سایت Nginx.
- فایل `Makefile`: متغیرها و هدف‌های تازه برای VM، استقرار و rollback.
- فایل `preflight.sh`: بررسی آمادگی پیش از کلاس (کد آموزشی نیست و این‌جا توضیح داده نمی‌شود).

ارتباط با جلسه‌ها: برنامه همان `churn.api:app` جلسه‌ی ۸ است. این بار به‌جای image جلسه‌ی ۹، یک **wheel** (بسته‌ی پایتون) و یک فهرست کتابخانه روی VM نصب می‌شود. مدل هنوز داخل برنامه نیست و هنگام روشن شدن از MLflow (جلسه‌ی ۷) گرفته می‌شود.

کامنت‌های داخل فایل‌ها عمداً انگلیسی هستند. شرح فارسی همه‌چیز در همین فایل است.

---

## مفهوم پایه: وضعیت دلخواه (desired state)

یک اسکریپت `bash` می‌گوید «این دستورها را به ترتیب بزن». یک playbook Ansible می‌گوید «سرور باید در این وضعیت باشد». مثلاً task نصب `nginx` نمی‌گوید «نصب کن»؛ می‌گوید `state: present` («باشد»). اگر Nginx هست، Ansible کاری نمی‌کند و `ok` می‌گوید. اگر نیست، نصب می‌کند و `changed` می‌گوید. به همین دلیل اجرای دوباره بی‌خطر است (**idempotency**).

```text
لپ‌تاپ شما                             VM (container)
  uv run ansible-playbook  --- SSH -->  python3 روی VM، ماژول را اجرا می‌کند
  deploy.yml                            -> نتیجه: ok / changed / failed
  inventory.ini (کجا)                   systemd + Nginx + برنامه
  templates/*.j2 (چه تنظیمی)
```

---

## فایل `vm/Dockerfile`

**کار فایل:** image «VM» تمرینی را می‌سازد: اوبونتو ۲۴٫۰۴ که systemd و SSH دارد و مثل یک سرور کوچک رفتار می‌کند. Ansible با SSH وارد آن می‌شود و سرویس‌های systemd را مدیریت می‌کند.

**اجرا:**

```bash
make vm-image
```

یادآوری صادقانه: این یک **container** است، نه VM واقعی. هسته را با میزبان شریک است (برای همین `uptime` عدد Docker host را نشان می‌دهد). ولی برای کار ما عملاً مثل VM است.

```dockerfile
FROM ubuntu:24.04
```

شروع از image رسمی اوبونتو ۲۴٫۰۴ (در نسخه‌ی کامل، نه `slim`).

```dockerfile
ENV DEBIAN_FRONTEND=noninteractive
```

وقتی `apt` نصب می‌کند سؤال نپرسد (در `docker build` کسی نیست جواب بدهد).

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus openssh-server sudo \
      python3 python3-venv python3-packaging ca-certificates curl nginx logrotate \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
```

یک `RUN` که چند کار می‌کند (با `&&` به هم وصل‌اند تا فقط یک لایه بسازد) و بسته‌های لازم را نصب می‌کند:

| بسته | چرا لازم است |
|---|---|
| `systemd`، `systemd-sysv` | مدیر سرویس؛ بدون آن `systemctl` کار نمی‌کند |
| `dbus` | systemd برای دستورهای کاربر معمولی (`systemctl status` بدون `sudo`) به آن نیاز دارد. بدون این بسته پیام `Failed to connect to bus` می‌آید |
| `openssh-server` | تا Ansible بتواند با SSH وارد شود |
| `sudo` | کاربر `ubuntu` با آن کارهای مدیریتی می‌کند |
| `python3`، `python3-venv` | Ansible روی سرور به پایتون نیاز دارد؛ و برنامه در یک virtualenv اجرا می‌شود |
| `python3-packaging` | ماژول `pip` در Ansible به آن نیاز دارد. بدون آن task نصب کتابخانه‌ها با پیام `Failed to import the required Python library (packaging)` شکست می‌خورد |
| `ca-certificates`، `curl` | اتصال امن HTTPS (برای pip) و ابزار تست (`curl`) داخل VM |
| `nginx`، `logrotate` | reverse proxy و چرخش لاگ (از قبل در image هستند تا task `apt` به اینترنت نیاز نداشته باشد) |

گزینه‌ی `--no-install-recommends` بسته‌های «پیشنهادی» را نصب نمی‌کند، پس image کوچک‌تر است. دو دستور آخر (`apt-get clean` و حذف `/var/lib/apt/lists`) فایل‌های موقت `apt` را پاک می‌کنند.

```dockerfile
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu && chmod 440 /etc/sudoers.d/ubuntu \
 && mkdir -p /home/ubuntu/.ssh && chmod 700 /home/ubuntu/.ssh && chown ubuntu:ubuntu /home/ubuntu/.ssh \
 && systemctl enable ssh \
 && systemctl disable nginx
```

چهار کار:

- کاربر `ubuntu` از قبل در image اوبونتو هست. به آن `sudo` بدون رمز می‌دهیم، مثل ماشین‌های ابری. Ansible با `become: true` از آن استفاده می‌کند.
- پوشه‌ی `~/.ssh` با دسترسی `700` (فقط خود کاربر) ساخته می‌شود؛ `make vm-up` کلید عمومی را بعداً داخل آن می‌گذارد.
- `systemctl enable ssh`: SSH هنگام بالا آمدن VM خودکار روشن شود.
- `systemctl disable nginx`: Nginx با نصب خودش روشن نشود؛ playbook آن را بعد از گذاشتن تنظیم درست روشن می‌کند. (وگرنه Nginx با سایت پیش‌فرضش بالا می‌آمد.)

```dockerfile
EXPOSE 22 80
```

یادداشتی برای خواننده: این image روی پورت‌های ۲۲ (SSH) و ۸۰ (Nginx) گوش می‌دهد. (پورت واقعی را `-p` در `docker run` باز می‌کند.)

```dockerfile
STOPSIGNAL SIGRTMIN+3
```

سیگنالی که `docker stop` می‌فرستد. systemd فقط با این سیگنال به‌صورت مرتب خاموش می‌شود.

```dockerfile
CMD ["/sbin/init"]
```

فرمان اجرا: به‌جای یک برنامه، خود `init` (یعنی systemd) پردازش اصلی container می‌شود و بقیه‌ی سرویس‌ها را بالا می‌آورد، درست مثل بوت شدن یک ماشین.

نکته: برای اجرا باید container را با `--privileged` بالا آورد (در هدف `vm-up` هست)؛ systemd به دسترسی به cgroup نیاز دارد. در محیط کلاس خوب است ولی روی سرور واقعی با این گزینه احتیاط کنید.

---

## فایل `deploy/ansible.cfg`

**کار فایل:** تنظیم‌های پیش‌فرض Ansible برای همین پوشه. Ansible این فایل را از **پوشه‌ی جاری** می‌خواند، برای همین دستورهایش را از داخل `deploy/` می‌زنیم.

```ini
[defaults]
inventory = inventory.ini
remote_user = ubuntu
private_key_file = ~/.ssh/mlops_vm
interpreter_python = /usr/bin/python3
stdout_callback = default
retry_files_enabled = False
```

| تنظیم | معنی |
|---|---|
| `inventory` | فهرست سرورها کدام فایل است (نیازی به `-i` در هر دستور نیست) |
| `remote_user` | با چه کاربری روی سرور SSH بزند |
| `private_key_file` | کلید خصوصی SSH (با `make vm-up` ساخته شده) |
| `interpreter_python` | پایتون سرور را مشخص می‌کند. بدون آن Ansible حدس می‌زند و هشدار می‌دهد |
| `stdout_callback = default` | قالب معمولی خروجی |
| `retry_files_enabled = False` | بعد از شکست فایل `.retry` نسازد (پوشه را شلوغ نکند) |

```ini
[ssh_connection]
ssh_args = -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPersist=60s
```

گزینه‌هایی که به `ssh` داده می‌شود:

- `StrictHostKeyChecking=accept-new`: کلید یک میزبان تازه را بار اول بپذیر (بدون سؤال)، ولی اگر بعداً **عوض شد** رد کن. این یعنی امنیت همیشگی ولی بدون زحمت بار اول.
- `ControlMaster=auto` و `ControlPersist=60s`: اتصال SSH را ۶۰ ثانیه باز نگه دار و برای taskهای بعدی دوباره استفاده کن. بدون آن برای هر task یک اتصال تازه باز می‌شود و playbook کند است.

---

## فایل `deploy/inventory.ini`

**کار فایل:** می‌گوید Ansible کدام سرورها را مدیریت کند.

```ini
[api]
mlops-vm ansible_host=127.0.0.1 ansible_port=2223
```

- `[api]`: نام یک **گروه**. در playbook با `hosts: api` به همه‌ی سرورهای این گروه اشاره می‌کنیم.
- `mlops-vm`: نام سرور در Ansible (فقط یک برچسب).
- `ansible_host=127.0.0.1`: آدرس واقعی برای SSH. VM ما روی همین لپ‌تاپ است.
- `ansible_port=2223`: پورتی که Docker برای SSH باز کرده (`-p 127.0.0.1:2223:22`).

برای یک VM واقعی (مثلاً Multipass) فقط همین خط عوض می‌شود: آدرس IP و پورت ۲۲. خود playbook دست نمی‌خورد؛ جدا بودن «کجا» از «چه» همین است.

---

## فایل `deploy/deploy.yml`

**کار فایل:** playbook اصلی. یک **play** دارد که روی گروه `api` اجرا می‌شود و VM را به وضعیت دلخواه می‌رساند.

**اجرا:**

```bash
make deploy
```

که همان `cd deploy && uv run ansible-playbook deploy.yml ...` است (پس از `make release`).

### سربرگ play و متغیرها

```yaml
- name: Deploy the churn API
  hosts: api
  become: true
```

- `name`: نام play؛ در خروجی دیده می‌شود.
- `hosts: api`: روی گروه `api` از inventory اجرا شود.
- `become: true`: taskها با `sudo` اجرا شوند (نصب بسته و ساخت فایل در `/etc` دسترسی root می‌خواهد).

```yaml
  vars:
    app_dir: /opt/churn-api
    api_port: 8000
    mlflow_uri: http://mlflow:5000
    model_uri: models:/churn@champion
    wheel: "{{ lookup('ansible.builtin.fileglob', '../dist/churn-*.whl', wantlist=True) | first }}"
```

| متغیر | معنی |
|---|---|
| `app_dir` | پوشه‌ی برنامه روی VM |
| `api_port` | پورت داخلی uvicorn (فقط روی `127.0.0.1`) |
| `mlflow_uri` | نشانی MLflow **از دید VM**. مثل جلسه‌ی ۹ نام سرویس و پورت داخلی شبکه‌ی Docker است، نه `localhost:5050`، چون `localhost` داخل VM یعنی خود VM |
| `model_uri` | کدام مدل سرویس شود: `models:/churn@champion` یا یک نسخه‌ی مشخص مثل `models:/churn/1` |
| `wheel` | مسیر فایل wheel که `make release` ساخته. `fileglob` فایل‌های مطابق الگو را روی **لپ‌تاپ** پیدا می‌کند و `first` اولی را برمی‌دارد |

هر متغیر با `-e` (مثلاً `-e model_uri=models:/churn/1`) از خط فرمان **بازنویسی** می‌شود؛ rollback همین است.

### taskها

هر task یک `name` دارد و یک **module** صدا می‌زند. جلوی هر module، پارامترهای آن است.

**۱. بسته‌ها**

```yaml
    - name: Packages are installed
      ansible.builtin.apt:
        name: [python3-venv, nginx, logrotate]
        state: present
```

module `apt`: مطمئن می‌شود سه بسته نصب‌اند (`present`). در image ما از قبل نصب‌اند، پس `ok` می‌شود و اینترنت لازم نیست. روی یک سرور خام همین task آن‌ها را نصب می‌کرد.

**۲. کاربر سرویس**

```yaml
    - name: Service user exists (no login shell)
      ansible.builtin.user:
        name: churn
        system: true
        shell: /usr/sbin/nologin
        create_home: false
```

module `user`: یک کاربر سیستمی به نام `churn` می‌سازد. `nologin` یعنی نمی‌شود با آن وارد شد؛ فقط برای اجرای سرویس است. اصل «کمترین دسترسی»: سرویس با root اجرا نمی‌شود (مثل کاربر `app` در جلسه‌ی ۹). `create_home: false` یعنی پوشه‌ی خانه نمی‌سازد.

**۳. پوشه‌ها**

```yaml
    - name: Folders exist
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: churn
        group: churn
        mode: "0755"
      loop: ["{{ app_dir }}", /var/log/churn-api, /etc/churn-api]
```

module `file` با `state: directory`: سه پوشه (برنامه، لاگ، تنظیم) می‌سازد و مالک آن‌ها `churn` است. `loop` همین task را برای هر عضو فهرست تکرار می‌کند و مقدار فعلی در `item` است. دسترسی `0755` یعنی مالک می‌نویسد، بقیه فقط می‌خوانند.

**۴. فایل requirements**

```yaml
    - name: Requirements file is copied
      ansible.builtin.copy:
        src: requirements.txt
        dest: "{{ app_dir }}/requirements.txt"
        mode: "0644"
```

module `copy`: فایل `deploy/requirements.txt` (که `make release` ساخته) را از لپ‌تاپ به VM می‌برد. این فایل فهرست قفل‌شده‌ی حدود ۹۰ کتابخانه با نسخه‌ی دقیق است (از `uv.lock`). اگر محتوا همان باشد، `ok` می‌شود.

**۵. نصب کتابخانه‌ها**

```yaml
    - name: Libraries are installed in the virtual environment
      ansible.builtin.pip:
        requirements: "{{ app_dir }}/requirements.txt"
        virtualenv: "{{ app_dir }}/venv"
        virtualenv_command: python3 -m venv
```

module `pip`: داخل یک virtualenv در `/opt/churn-api/venv` (اگر نبود می‌سازد) همه‌ی کتابخانه‌ها را نصب می‌کند. این task در بار اول طولانی‌ترین است (حدود دو دقیقه، چون حدود ۹۰ بسته از PyPI دانلود می‌شود). `virtualenv_command: python3 -m venv` یعنی از `venv` خود پایتون استفاده کن، نه ابزار جداگانه‌ای.

**۶. کپی wheel**

```yaml
    - name: App wheel is copied
      ansible.builtin.copy:
        src: "{{ wheel }}"
        dest: "{{ app_dir }}/{{ wheel | basename }}"
        mode: "0644"
      register: wheel_copy
```

wheel یعنی بسته‌ی کد خودمان. `register: wheel_copy` نتیجه‌ی این task را در متغیری ذخیره می‌کند (مثلاً `wheel_copy.changed`). `wheel | basename` فقط نام فایل را از مسیر جدا می‌کند. چون wheel قابل‌بازتولید است (بایت‌به‌بایت یکسان)، اگر کد عوض نشده باشد این task هم `ok` است.

**۷. نصب wheel (شرطی)**

```yaml
    - name: Our app is installed from the wheel (only when the wheel changed)
      ansible.builtin.pip:
        name: "{{ app_dir }}/{{ wheel | basename }}"
        virtualenv: "{{ app_dir }}/venv"
        extra_args: --no-deps --force-reinstall
      when: wheel_copy.changed
      notify: Restart churn-api
```

- `when: wheel_copy.changed`: فقط اگر wheel تازه است نصب کن؛ وگرنه `skipping`. (برای همین در اجرای دوم `skipped=1` می‌بینید.)
- `--no-deps`: کتابخانه‌ها را دوباره نصب نکن (قبلاً نصب شده‌اند). `--force-reinstall`: حتی اگر شماره‌ی نسخه همان است (`0.1.0`) دوباره نصب کن، چون کد عوض شده است.
- `notify`: اگر این task `changed` شد، handler `Restart churn-api` را صدا بزن (توضیح پایین).

**۸. فایل تنظیم**

```yaml
    - name: Settings file (model, MLflow address)
      ansible.builtin.template:
        src: templates/churn-api.env.j2
        dest: /etc/churn-api/churn-api.env
        owner: root
        group: churn
        mode: "0640"
      notify: Restart churn-api
```

module `template`: قالب Jinja2 را روی لپ‌تاپ پر می‌کند و نتیجه را روی VM می‌گذارد. مالک `root` و گروه `churn` و دسترسی `0640` یعنی فقط root می‌نویسد، سرویس می‌خواند، بقیه هیچ. (محتوای تنظیم‌ها ممکن است رمز باشد؛ قاعده‌ی خوب همین است.) با تغییر مدل یا آدرس، فایل عوض می‌شود و سرویس restart می‌شود.

**۹. unit سرویس systemd**

```yaml
    - name: systemd unit
      ansible.builtin.template:
        src: templates/churn-api.service.j2
        dest: /etc/systemd/system/churn-api.service
        mode: "0644"
      notify: Restart churn-api
```

فایل unit را در `/etc/systemd/system/` می‌گذارد، همان جایی که systemd سرویس‌های مدیر سیستم را می‌خواند.

**۱۰. چرخش لاگ**

```yaml
    - name: Log rotation for the API log
      ansible.builtin.template:
        src: templates/churn-api.logrotate.j2
        dest: /etc/logrotate.d/churn-api
        mode: "0644"
```

تنظیم `logrotate` را می‌گذارد. این ابزار روزی یک بار خودش (با زمان‌بند سیستم) اجرا می‌شود، پس نیازی به restart نیست.

**۱۱ تا ۱۳. Nginx**

```yaml
    - name: Nginx site (reverse proxy on port 80)
      ansible.builtin.template:
        src: templates/nginx-churn-api.conf.j2
        dest: /etc/nginx/sites-available/churn-api
        mode: "0644"
      notify: Reload nginx

    - name: Nginx site is enabled, the default site is not
      ansible.builtin.file:
        src: /etc/nginx/sites-available/churn-api
        dest: /etc/nginx/sites-enabled/churn-api
        state: link
      notify: Reload nginx

    - name: Default Nginx site is removed
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      notify: Reload nginx
```

در Debian/Ubuntu تنظیم‌ها در `sites-available` نگه داشته می‌شوند و Nginx فقط آن‌هایی را می‌خواند که در `sites-enabled` یک **لینک نمادین** (symlink) دارند. سه task:

1. سایت ما را در `sites-available` می‌گذارد.
2. با `state: link` لینک آن را در `sites-enabled` می‌سازد.
3. سایت پیش‌فرض Nginx را با `state: absent` پاک می‌کند، چون روی همان پورت ۸۰ گوش می‌دهد و با سایت ما تداخل می‌کرد.

هر سه `notify: Reload nginx` دارند.

**۱۴. روشن کردن سرویس‌ها**

```yaml
    - name: Services are enabled and running
      ansible.builtin.systemd_service:
        name: "{{ item }}"
        enabled: true
        state: started
        daemon_reload: true
      loop: [churn-api, nginx]
```

module `systemd_service`:

- `enabled: true`: بعد از reboot خودکار بالا بیاید.
- `state: started`: همین الان روشن باشد (اگر روشن است کاری نکن).
- `daemon_reload: true`: systemd فایل‌های unit را دوباره بخواند (لازم است چون unit را تازه گذاشته‌ایم).

در اجرای اول این task دو بار `changed` می‌شود (هر سرویس یک بار)؛ در اجرای‌های بعد `ok`.

### handlerها

```yaml
  handlers:
    - name: Restart churn-api
      ansible.builtin.systemd_service:
        name: churn-api
        state: restarted
        daemon_reload: true

    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
```

**handler** taskی است که فقط وقتی اجرا می‌شود که یک task با `notify` آن را صدا زده باشد (یعنی چیزی را `changed` کرده). ویژگی‌ها:

- آخر همه‌ی taskها اجرا می‌شوند، و حتی اگر ده task آن را صدا بزنند فقط **یک بار**.
- `Restart churn-api` در بار اول و هنگام تغییر مدل/تنظیم/کد اجرا می‌شود و در اجرای بی‌تغییر هرگز.
- `Reload nginx` فقط تنظیم را دوباره می‌خواند و اتصال‌ها قطع نمی‌شوند (سبک‌تر از restart).

### post_tasks

```yaml
  post_tasks:
    - name: The API is ready behind Nginx
      ansible.builtin.uri:
        url: http://127.0.0.1/ready
        return_content: true
      register: ready
      retries: 20
      delay: 3
      until: ready.status == 200
```

بعد از handlerها اجرا می‌شود. module `uri` از **داخل VM** آدرس `/ready` (پورت ۸۰، یعنی از پشت Nginx) را صدا می‌زند. `until: ready.status == 200` یعنی تا جواب ۲۰۰ نگرفتی تکرار کن؛ `retries: 20` و `delay: 3` یعنی حداکثر ۲۰ بار با ۳ ثانیه فاصله (یک دقیقه). اگر هیچ‌وقت ۲۰۰ نشد، **کل استقرار شکست می‌خورد**؛ این همان «تست دود» است. به همین دلیل آدرس اشتباه MLflow (جواب `503`) در همین نقطه گرفته می‌شود و نه وقتی که کاربر شکایت کند. خط قرمز `FAILED - RETRYING` در حالت عادی فقط یعنی برنامه هنوز مدل را بار می‌کند.

```yaml
    - name: Show the served model version
      ansible.builtin.debug:
        msg: "ready: {{ ready.json }}"
      when: not ansible_check_mode   # --check does not call the API
```

نسخه‌ی مدلی که سرویس می‌دهد را چاپ می‌کند. شرط `when: not ansible_check_mode` لازم است: در حالت `--check` درخواستی فرستاده نمی‌شود، پس `ready.json` وجود ندارد و بدون این شرط اجرای آزمایشی با خطا می‌ایستاد.

---

## قالب `deploy/templates/churn-api.env.j2`

**کار فایل:** فایل تنظیم محیطی سرویس. قالب‌های `.j2` (Jinja2) متن عادی هستند که جای `{{ ... }}` در آن‌ها با مقدار متغیر پر می‌شود.

```jinja
MLFLOW_TRACKING_URI={{ mlflow_uri }}
MODEL_URI={{ model_uri }}
MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false
MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false
MLFLOW_DISABLE_AGENT_HINT=1
```

- `MLFLOW_TRACKING_URI`: نشانی MLflow (از `mlflow_uri`).
- `MODEL_URI`: کدام مدل را بار کند (از `model_uri`). همین یک خط با rollback عوض می‌شود.
- سه خط آخر ثابت‌اند: همان تنظیم‌های MLflow که از جلسه‌های ۸ و ۹ می‌شناسید. اولی دانلود artifact از طریق سرور را درست می‌کند، دوم نوار پیشرفت را خاموش می‌کند تا لاگ شلوغ نشود، سومی پیام راهنمای اضافی را حذف می‌کند.

فایل را `systemd` با `EnvironmentFile=` می‌خواند: هر خط `نام=مقدار` یک متغیر محیطی برای برنامه می‌شود.

---

## قالب `deploy/templates/churn-api.service.j2`

**کار فایل:** unit سرویس: به systemd می‌گوید برنامه را چطور اجرا و نگهداری کند.

```ini
[Unit]
Description=Churn prediction API (uvicorn)
After=network-online.target
Wants=network-online.target
```

بخش `[Unit]`: توضیح سرویس (در `systemctl status` دیده می‌شود)، و `After`/`Wants` یعنی بعد از آماده شدن شبکه شروع کن (برنامه هنگام روشن شدن به MLflow وصل می‌شود).

```ini
[Service]
User=churn
Group=churn
WorkingDirectory={{ app_dir }}
EnvironmentFile=/etc/churn-api/churn-api.env
```

- `User` و `Group`: با کاربر `churn` اجرا شود، نه root.
- `WorkingDirectory`: پوشه‌ی کاری.
- `EnvironmentFile`: متغیرهای محیطی را از فایل تنظیم بخوان.

```ini
ExecStart={{ app_dir }}/venv/bin/uvicorn churn.api:app --host 127.0.0.1 --port {{ api_port }} --no-access-log
```

فرمان اجرا. uvicorn داخل virtualenv و **فقط روی `127.0.0.1`** گوش می‌دهد؛ یعنی از بیرون VM دیده نمی‌شود و تنها راه ورود، Nginx است. (در جلسه‌ی ۹ داخل container `0.0.0.0` بود، چون Docker پورت را جدا مدیریت می‌کرد. اینجا لازم نیست.) `--no-access-log` مثل جلسه‌ی ۸: خود برنامه لاگ JSON می‌نویسد.

```ini
StandardOutput=append:/var/log/churn-api/api.log
StandardError=append:/var/log/churn-api/api.log
```

خروجی و خطای برنامه به‌جای `journalctl` به یک فایل اضافه (`append`) شود. برای همین `journalctl -u churn-api` فقط پیام‌های خود systemd (شروع، توقف) را نشان می‌دهد و لاگ برنامه در این فایل است. همین فایل را logrotate می‌چرخاند.

```ini
Restart=on-failure
RestartSec=3
```

اگر برنامه با خطا تمام شد یا کشته شد، systemd بعد از ۳ ثانیه دوباره روشنش کند. (اگر شما با `systemctl stop` عمداً خاموشش کنید، دوباره روشن نمی‌شود.) این همان خاصیتی است که در crash test دیدید.

```ini
[Install]
WantedBy=multi-user.target
```

با `enable` این سرویس در حالت عادی بوت (`multi-user.target`) خودکار روشن می‌شود.

---

## قالب `deploy/templates/churn-api.logrotate.j2`

**کار فایل:** قاعده‌ی چرخش لاگ؛ بدون آن فایل لاگ بی‌نهایت بزرگ می‌شود و دیسک پر می‌شود.

```text
/var/log/churn-api/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

| گزینه | معنی |
|---|---|
| `daily` | هر روز یک بار |
| `rotate 7` | هفت نسخه‌ی قدیمی را نگه دار، قدیمی‌تر را پاک کن |
| `compress` | نسخه‌های قدیمی را فشرده کن |
| `delaycompress` | نسخه‌ی اخیر (`.1`) را یک دور دیرتر فشرده کن (برنامه ممکن است هنوز در حال نوشتن باشد) |
| `missingok` | اگر فایل لاگ نبود خطا نده |
| `notifempty` | لاگ خالی را نچرخان |
| `copytruncate` | لاگ را کپی کن و فایل اصلی را خالی کن؛ برنامه همچنان در همان فایل می‌نویسد و restart لازم نیست |

نکته‌ی `copytruncate`: چون systemd فایل را با `append` باز نگه داشته، این روش ساده‌ترین راه است. (ممکن است چند خط لحظه‌ی کپی از دست برود؛ برای ما قابل‌قبول است.)

---

## قالب `deploy/templates/nginx-churn-api.conf.j2`

**کار فایل:** تنظیم Nginx به‌عنوان **reverse proxy**: درخواست‌ها را روی پورت ۸۰ می‌گیرد و به uvicorn می‌دهد.

```nginx
server {
    listen 80 default_server;
    server_name _;
```

یک «سایت» (`server`) که روی پورت ۸۰ گوش می‌دهد. `default_server` یعنی هر درخواستی (با هر نام میزبان) به این سایت می‌رسد. `server_name _` نامی است که هیچ‌وقت با نام واقعی یکی نمی‌شود، یعنی «هر نامی».

```nginx
    access_log /var/log/nginx/churn-api.access.log;
    error_log  /var/log/nginx/churn-api.error.log;
```

لاگ‌های جداگانه برای این سایت: هر درخواست یک خط در `access_log`، و خطاها (مثلاً برنامه‌ی پشتی در دسترس نیست) در `error_log`. برای عیب‌یابی اول به اینجا نگاه می‌کنیم.

```nginx
    location / {
        proxy_pass http://127.0.0.1:{{ api_port }};
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
    }
```

همه‌ی مسیرها (`/`) را به uvicorn می‌فرستد:

- `proxy_pass`: مقصد، یعنی `http://127.0.0.1:8000`.
- `proxy_set_header Host`: نام میزبان اصلی درخواست را به برنامه برساند.
- `X-Forwarded-For`: نشانی IP واقعی مشتری را در یک هدر بگذارد (وگرنه برنامه همیشه `127.0.0.1` یعنی خود Nginx را می‌بیند).
- `proxy_read_timeout 30s`: اگر برنامه ۳۰ ثانیه جواب نداد، قطع کن و خطا (۵۰۴) بده.

وقتی برنامه‌ی پشتی خاموش یا در حال بالا آمدن است، Nginx خودش `502 Bad Gateway` می‌دهد. برای همین بعد از restart چند ثانیه ۵۰۲ می‌بینید.

---

## فایل `Makefile`

**کار فایل:** همان Makefile جلسه‌ی ۹ است (هدف‌های `data` تا `push`) به‌علاوه‌ی متغیرها و شش هدف تازه. فقط بخش جدید توضیح داده می‌شود.

```makefile
.PHONY: ... vm-image vm-up vm-ssh release deploy rollback
```

شش نام تازه به فهرست هدف‌هایی که نام فایل نیستند اضافه شده است.

```makefile
VM_NAME ?= mlops-vm
VM_IMAGE ?= mlops/practice-vm:24.04
VM_DIR ?= $(HOME)/mlops-lab/s10/vm
VM_SSH_PORT ?= 2223
VM_HTTP_PORT ?= 8090
VM_KEY ?= $(HOME)/.ssh/mlops_vm
KNOWN_HOSTS ?= $(HOME)/.ssh/known_hosts
```

علامت `?=` یعنی فقط اگر از بیرون مقدار داده نشده باشد (مثلاً `make vm-up VM_SSH_PORT=2224`).

| متغیر | معنی |
|---|---|
| `VM_NAME` | نام container و نام میزبان VM |
| `VM_IMAGE` | نام و tag image VM |
| `VM_DIR` | پوشه‌ای که `vm/Dockerfile` در آن است (برای ساخت image) |
| `VM_SSH_PORT` | پورت لپ‌تاپ که به SSH داخل VM می‌رسد |
| `VM_HTTP_PORT` | پورت لپ‌تاپ که به Nginx داخل VM می‌رسد |
| `VM_KEY` | مسیر کلید خصوصی SSH (کلید عمومی همان با پسوند `.pub`) |
| `KNOWN_HOSTS` | فایل میزبان‌های شناخته‌شده‌ی SSH |

```makefile
vm-image:
	docker build -t $(VM_IMAGE) $(VM_DIR)
```

هدف `vm-image`: image را از `vm/Dockerfile` می‌سازد. آرگومان آخر پوشه‌ی build context است.

```makefile
vm-up:
	docker run -d --name $(VM_NAME) --hostname $(VM_NAME) --privileged --network $(NETWORK) \
	  -p 127.0.0.1:$(VM_SSH_PORT):22 -p 127.0.0.1:$(VM_HTTP_PORT):80 $(VM_IMAGE)
	test -f $(VM_KEY) || ssh-keygen -q -t ed25519 -N "" -C mlops-vm -f $(VM_KEY)
	docker cp $(VM_KEY).pub $(VM_NAME):/home/ubuntu/.ssh/authorized_keys
	docker exec $(VM_NAME) chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
	ssh-keygen -R "[127.0.0.1]:$(VM_SSH_PORT)" -f $(KNOWN_HOSTS) >/dev/null 2>&1 || true
```

هدف `vm-up` پنج دستور دارد:

1. `docker run`: container VM را در پس‌زمینه (`-d`) با نام و hostname برابر `mlops-vm` اجرا می‌کند. `--privileged` برای systemd لازم است. `--network mlops-lab` آن را کنار MLflow می‌گذارد تا `http://mlflow:5000` از داخل VM کار کند. دو `-p` پورت SSH و HTTP را فقط روی `127.0.0.1` لپ‌تاپ باز می‌کنند.
2. `test -f ... || ssh-keygen ...`: اگر کلید SSH هنوز نیست، یک جفت‌کلید `ed25519` بدون رمز (`-N ""`) می‌سازد. اگر هست، کاری نمی‌کند (کلید را عوض نمی‌کند).
3. `docker cp`: کلید عمومی را به عنوان `authorized_keys` کاربر `ubuntu` داخل VM می‌گذارد.
4. `docker exec ... chown`: مالک فایل را `ubuntu` می‌کند (وگرنه SSH آن را رد می‌کند).
5. خط `ssh-keygen -R`: کلید میزبان قدیمی را از `known_hosts` پاک می‌کند. بخش `|| true` یعنی اگر چیزی برای پاک کردن نبود (یا فایل `known_hosts` هنوز وجود نداشت) make خطا نگیرد و ادامه دهد. دلیل: هر VM تازه، کلید میزبان تازه دارد و SSH با کلید قدیمی هشدار `REMOTE HOST IDENTIFICATION HAS CHANGED` می‌دهد.

```makefile
vm-ssh:
	ssh -i $(VM_KEY) -p $(VM_SSH_PORT) -o UserKnownHostsFile=$(KNOWN_HOSTS) -o StrictHostKeyChecking=accept-new ubuntu@127.0.0.1
```

هدف `vm-ssh`: با کلید ما به عنوان `ubuntu` وارد VM می‌شود (`-i` کلید، `-p` پورت).

```makefile
release:
	rm -rf dist
	uv build --wheel
	uv export -q --no-dev --no-emit-project --no-hashes --format requirements-txt -o deploy/requirements.txt
```

هدف `release`: دو چیز را آماده‌ی ارسال می‌کند.

- `rm -rf dist` و `uv build --wheel`: پوشه‌ی قدیمی را پاک و wheel برنامه را در `dist/` می‌سازد (`churn-0.1.0-py3-none-any.whl`).
- `uv export ...`: کتابخانه‌های قفل‌شده را از `uv.lock` به شکل `requirements.txt` در می‌آورد. `--no-dev` ابزارهای توسعه را حذف می‌کند، `--no-emit-project` خود پروژه را (چون wheel جداست)، `--no-hashes` را برای سادگی گذاشته‌ایم، `-q` ساکت است.

```makefile
deploy: release
	cd deploy && uv run ansible-playbook deploy.yml -e ansible_port=$(VM_SSH_PORT) --private-key $(VM_KEY)
```

هدف `deploy`: عبارت `deploy: release` یعنی اول `release` اجرا شود. بعد در پوشه‌ی `deploy` playbook را می‌زند. `-e ansible_port=...` و `--private-key` مقدار متغیرهای Makefile را به Ansible می‌دهند، پس اگر پورت را عوض کردید (`VM_SSH_PORT=2224`) استقرار هم دنبال آن می‌آید.

```makefile
rollback:
	cd deploy && uv run ansible-playbook deploy.yml -e ansible_port=$(VM_SSH_PORT) --private-key $(VM_KEY) \
	  -e model_uri=models:/churn/$(VERSION)
```

هدف `rollback`: همان استقرار، ولی با `-e model_uri=models:/churn/$(VERSION)` که مدل را روی یک نسخه‌ی مشخص می‌گذارد. استفاده: `make rollback VERSION=1`. فقط فایل تنظیم عوض می‌شود و سرویس restart می‌شود، پس سریع است. این هدف `release` را اجرا نمی‌کند (کد عوض نمی‌شود)، اما برای کار کردن به پوشه‌ی `dist/` از قبل نیاز دارد. برگشت به جلو: `make deploy` (به `@champion` برمی‌گردد).

جلوی خط‌های دستور باید TAB باشد، نه فاصله.

---

## پرسش‌هایی برای فکر کردن

1. اگر یک نفر دستی داخل VM فایل `/etc/churn-api/churn-api.env` را ویرایش کند و بعد `make deploy` بزنیم، چه می‌شود؟ این برای «منبع حقیقت» (source of truth) چه معنایی دارد؟
2. چرا `Reload nginx` یک handler است و در خود task قرار نگرفته؟ اگر ده task تنظیم Nginx عوض کنند، چند بار reload می‌شود؟
3. uvicorn فقط روی `127.0.0.1` گوش می‌دهد. اگر آن را به `0.0.0.0` عوض کنیم و پورت ۸۰۰۰ را هم در `docker run` باز کنیم، چه خطری پیش می‌آید و Nginx چه چیزی را از دست می‌دهد؟
4. فرض کنید `mlflow_uri` را `http://localhost:5050` گذاشتید. استقرار کجا و چطور شکست می‌خورد؟ چرا این بهتر از آن است که شکست نخورد و سرویس خراب بالا بیاید؟
5. تفاوت `Restart=on-failure` با `Restart=always` چیست؟ چه موقع `always` ناخوشایند است؟

</div>
