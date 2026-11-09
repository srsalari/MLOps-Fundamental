<div dir="rtl">

# آماده‌سازی جلسه‌ی ۲

قبل از شروع آزمایشگاه جلسه‌ی ۲ این گام‌ها را انجام دهید. جلسه‌ی ۲ سه چیز تازه لازم دارد: Docker (برای سرویس Gitea)، فایل‌های به‌روز این مخزن، و سه ابزار پایتون (ruff، pytest، pre-commit).

> کاربران Windows همه‌ی دستورها را داخل پنجره‌ی Ubuntu (WSL) اجرا کنند، نه PowerShell.
> اگر ابتدای خط `PS C:\...>` می‌بینید در PowerShell هستید؛ در Ubuntu چیزی شبیه `name@pc:~$` می‌بینید.

## ۱. نصب Docker

### Ubuntu و WSL

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 docker-buildx
```

```bash
sudo systemctl enable --now docker && sudo usermod -aG docker $USER
```

بعد از این دستور یک بار خارج و دوباره وارد شوید. در WSL: پنجره‌ی Ubuntu را ببندید، در PowerShell بزنید `wsl --shutdown` و Ubuntu را دوباره باز کنید.

Docker Desktop را روی Windows نصب نکنید؛ در این دوره Docker داخل خود Ubuntu اجرا می‌شود.

### macOS

با [Homebrew](https://brew.sh):

```bash
brew install colima docker docker-compose docker-buildx
```

```bash
mkdir -p ~/.docker/cli-plugins && ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
```

```bash
colima start --cpu 4 --memory 8
```

اگر Docker Desktop از قبل نصب است، همان کافی است و لازم نیست Colima نصب کنید؛ فقط بازش کنید.

## ۲. بررسی Docker

```bash
docker version && docker compose version
```

```bash
docker run --rm hello-world
```

باید `Hello from Docker!` را ببینید.

## ۳. به‌روزرسانی مخزن دوره

اگر قبلاً clone کرده‌اید:

```bash
git -C ~/mlops-lab pull
```

اگر نه:

```bash
git clone https://github.com/srsalari/MLOps-Fundamental.git ~/mlops-lab
```

## ۴. دریافت image سرویس Gitea

حدود ۲۷۰ مگابایت است:

```bash
cd ~/mlops-lab/compose && cp -n .env.example .env; docker compose pull gitea
```

```bash
docker images | grep gitea
```

باید `gitea/gitea` با tag `1.27.3` را ببینید.

اگر دریافت با خطای 403 یا timeout متوقف شد، فایل image را از مدرس بگیرید و این‌طور بار کنید:

```bash
gunzip -c gitea-1.27.3.tar.gz | docker load
```

## ۵. ابزارهای پایتون

این سه دستور ابزارها را دانلود و در حافظه‌ی uv نگه می‌دارند تا نصبشان در آزمایشگاه سریع باشد. به پروژه‌ی شما دست نمی‌زنند:

```bash
uvx ruff --version
```

```bash
uvx pytest --version
```

```bash
uvx pre-commit --version
```

## ۶. بررسی نهایی

```bash
git --version && uv --version && make --version | head -1 && docker compose version
```

```bash
cd ~/work/churn-mlops && make train
```

دستور آخر باید این را بدهد:

```
{'roc_auc': 0.802, 'f1': 0.5969}
```

اگر پروژه‌ی جلسه‌ی ۱ را ندارید، اول [راهنمای جلسه‌ی ۱](../s01/README.md) را انجام دهید.

## ویرایشگر

برای ویرایش فایل‌ها از VS Code یا `nano` استفاده کنید. TextEdit و Notepad مناسب نیستند، چون حروف را خودکار بزرگ می‌کنند و Tab می‌گذارند، و فایل‌های YAML با Tab خطا می‌دهند.

کار با `nano`: ذخیره با Ctrl+O و Enter، خروج با Ctrl+X.

## خطاهای رایج

| نشانه | راه‌حل |
|---|---|
| `permission denied ... docker.sock` | خروج و ورود دوباره؛ در WSL دستور `wsl --shutdown` در PowerShell |
| `Cannot connect to the Docker daemon` | Ubuntu: `sudo systemctl start docker`؛ مک: `colima start` یا باز کردن Docker Desktop |
| `System has not been booted with systemd` (WSL) | `sudo service docker start` |
| `The token '&&' is not a valid statement separator` | دستور را در PowerShell زده‌اید؛ پنجره‌ی Ubuntu را باز کنید |
| `docker compose pull` خطای 403 یا timeout داد | فایل image را از مدرس بگیرید (گام ۴) |
| `command not found: uvx` | ترمینال را ببندید و باز کنید؛ اگر باز هم نبود `uv` را دوباره نصب کنید ([جلسه‌ی ۱](../s01/README.md)) |

بعد از این گام‌ها به [راهنمای آزمایشگاه جلسه‌ی ۲](README.md) بروید.

</div>
