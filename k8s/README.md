<div dir="rtl">

# راهنمای تنظیمات Kubernetes

این پوشه سه فایل تنظیمات برای جلسه‌های ۱۱ تا ۱۳ دارد: خوشه‌ی کوچک **kind**، ingress controller به نام **Traefik** و پشته‌ی مانیتورینگ **Prometheus و Grafana**. توضیح انگلیسی هر خط داخل خود فایل‌ها هم هست.

| فایل | کار آن | جلسه |
| --- | --- | --- |
| `kind-config.yaml` | ساخت خوشه‌ی تک‌گره‌ای و باز کردن پورت‌ها روی لپ‌تاپ | ۱۱ |
| `traefik-values.yaml` | تنظیم Helm برای Traefik | ۱۲ |
| `monitoring-values.yaml` | تنظیم Helm برای kube-prometheus-stack | ۱۳ |

نکته: فایل‌های `*-values.yaml` برای **Helm** هستند (مقدارهایی که chart را تنظیم می‌کنند)، ولی `kind-config.yaml` را به `kind` می‌دهیم. خوشه را معمولاً با اسکریپت `scripts/kind-up.sh` می‌سازید که نسخه‌ی image گره را از `versions.env` می‌خواند.

## فایل `kind-config.yaml` (جلسه‌ی ۱۱)

ابزار kind هر گره‌ی Kubernetes را داخل یک container Docker اجرا می‌کند. برای لپ‌تاپ ۱۶ گیگ یک گره کافی است.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: mlops
nodes:
  - role: control-plane
    labels:
      ingress-ready: "true"
```

- مقدار `name: mlops` نام خوشه است؛ context دستور kubectl می‌شود `kind-mlops`.
- یک گره با نقش `control-plane` هم مدیر و هم کارگر است.
- برچسب `ingress-ready: "true"` را Traefik در `nodeSelector` خود می‌خواهد تا روی همین گره اجرا شود.

```yaml
extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
    listenAddress: "127.0.0.1"
  - containerPort: 30443
    hostPort: 8443
    listenAddress: "127.0.0.1"
```

گره خودش یک container است، پس برای دسترسی از لپ‌تاپ باید پورت‌ها را منتشر کنیم. پورت‌های NodePort به نام `30080` و `30443` که Traefik می‌گیرد، روی پورت‌های `8080` و `8443` لپ‌تاپ دیده می‌شوند. مقدار `listenAddress` هم فقط به همین لپ‌تاپ اجازه‌ی اتصال می‌دهد. بنابراین سرویس‌های شما در مرورگر از نشانی `http://localhost:8080` در دسترس‌اند.

## فایل `traefik-values.yaml` (جلسه‌ی ۱۲)

سرویس Traefik درخواست‌های ورودی را بر اساس اشیای Ingress به سرویس‌های درون خوشه می‌رساند. این جایگزین ingress-nginx است که دیگر نگهداری نمی‌شود.

```yaml
deployment:
  replicas: 1
service:
  type: NodePort
ports:
  web:
    nodePort: 30080
  websecure:
    nodePort: 30443
```

- مقدار `replicas: 1` یعنی یک نسخه برای آزمایشگاه کافی است.
- مقدار `type: NodePort` لازم است چون kind load balancer ابری ندارد؛ پورت ثابت روی گره باز می‌شود.
- مقدارهای `30080` (HTTP) و `30443` (HTTPS) دقیقاً همان‌هایی هستند که `kind-config.yaml` به لپ‌تاپ وصل کرده است. اگر یکی را عوض کنید باید دیگری را هم عوض کنید.

```yaml
ingressClass:
  enabled: true
  isDefaultClass: true
providers:
  kubernetesIngress:
    enabled: true
  kubernetesGateway:
    enabled: false
nodeSelector:
  ingress-ready: "true"
```

- گزینه‌ی `isDefaultClass: true` یعنی Ingressهایی که کلاس نمی‌نویسند هم به Traefik می‌رسند.
- گزینه‌ی `kubernetesIngress` اشیای معمولی Ingress را می‌خواند.
- گزینه‌ی `kubernetesGateway` که خاموش است، یعنی Gateway API فقط به‌عنوان پیش‌نمایش در کلاس دیده می‌شود.
- بخش `nodeSelector` با برچسب گره‌ی kind هماهنگ است.
- بخش `resources` مصرف حافظه را کوچک نگه می‌دارد (حداکثر ۲۵۶ مگابایت).

## فایل `monitoring-values.yaml` (جلسه‌ی ۱۳)

این فایل chart به نام kube-prometheus-stack را سبک می‌کند تا کل مانیتورینگ حدود ۱ گیگابایت RAM بخورد.

> **توجه:** آزمایشگاه جلسه‌ی ۱۳ از این فایل استفاده **نمی‌کند**. آنجا Prometheus و Grafana با Docker Compose (پوشه‌ی `monitoring/` در `s13/`) کنار API اجرا می‌شوند، چون سبک‌تر است (حدود ۰٫۴ تا ۰٫۸ گیگابایت و نیازی به cluster ندارد). این فایل برای کسانی است که بخواهند همان کار را روی Kubernetes با `scripts/kind-up.sh --monitoring` تجربه کنند؛ در کلاس تست نشده است.

```yaml
alertmanager:
  enabled: false
nodeExporter:
  enabled: false
defaultRules:
  create: false
kubeEtcd: {enabled: false}
kubeScheduler: {enabled: false}
kubeControllerManager: {enabled: false}
kubeProxy: {enabled: false}
```

بخش‌هایی که در این دوره لازم نیستند خاموش شده‌اند: Alertmanager، node-exporter، قانون‌های هشدار پیش‌فرض و مانیتور اجزای control plane که در kind به روش معمول قابل خواندن نیستند.

```yaml
prometheus:
  prometheusSpec:
    retention: 2d
    scrapeInterval: 15s
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
```

- مقدار `retention: 2d` متریک‌ها را فقط دو روز نگه می‌دارد.
- مقدار `scrapeInterval: 15s` یعنی Prometheus هر ۱۵ ثانیه متریک‌ها را می‌خواند.
- سه گزینه‌ی `...SelectorNilUsesHelmValues: false` باعث می‌شوند ServiceMonitor و PodMonitor و قانون‌هایی که دانشجوها در هر namespace می‌سازند، بدون برچسب خاص دیده شوند. اگر این‌ها نبود، مانیتور سرویس استنتاج شما نادیده گرفته می‌شد.

```yaml
grafana:
  adminPassword: mlops-lab   # LAB-ONLY
  defaultDashboardsEnabled: false
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
```

- رمز `adminPassword` فقط برای آزمایشگاه است و در محیط واقعی نباید استفاده شود.
- گزینه‌ی `defaultDashboardsEnabled: false` داشبوردهای آماده را خاموش می‌کند؛ دانشجوها داشبورد خودشان را می‌سازند.
- مولفه‌ی sidecar داشبوردها را از ConfigMapهای دارای برچسب `grafana_dashboard=1` در همه‌ی namespaceها (`ALL`) می‌خواند.

بخش‌های `resources` در هر جزء (prometheusOperator، prometheus، grafana و kube-state-metrics) مقدار `requests` و `limits` حافظه را کوچک نگه می‌دارند تا همه با هم روی لپ‌تاپ جا شوند.

## پرسش‌هایی برای فکر کردن

۱. چرا پورت `30080` در دو فایل `kind-config.yaml` و `traefik-values.yaml` آمده است؟
۲. اگر `serviceMonitorSelectorNilUsesHelmValues` را `true` کنیم، چه اتفاقی برای مانیتور سرویس شما می‌افتد؟
۳. چرا در kind به `type: NodePort` نیاز داریم و `LoadBalancer` کار نمی‌کند؟

</div>
