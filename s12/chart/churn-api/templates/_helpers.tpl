{{/*
Name helpers. A file that starts with _ makes no Kubernetes object; it only holds
named templates that the other files call with {{ include "name" . }}.
*/}}

{{/* The chart name: churn-api */}}
{{- define "churn-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The name of every object. With release name "churn-api" it is "churn-api" (the same
names as in session 11). With release "prod" it is "prod-churn-api".
*/}}
{{- define "churn-api.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels for selecting the pods. Never change them after the first install. */}}
{{- define "churn-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "churn-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Labels on every object (the selector labels + who made it). */}}
{{- define "churn-api.labels" -}}
{{ include "churn-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
