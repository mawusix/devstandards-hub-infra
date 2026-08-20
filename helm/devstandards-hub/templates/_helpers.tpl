{{/*
Standard chart name/fullname/label helpers, shared by every template so the
Deployment's selector, the Service's selector, the HPA/PDB's target, and the
NetworkPolicy's podSelector all agree on the same labels without repeating them.
*/}}

{{- define "devstandards-hub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "devstandards-hub.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "devstandards-hub.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "devstandards-hub.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.app.version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
WHY selector labels are a separate, smaller set from the full labels above: a
Deployment/Service/PDB/NetworkPolicy selector is immutable (or at least must stay
stable across upgrades) — it must never include a label like app.kubernetes.io/version
that changes on every app release, or a Helm upgrade that only bumps the app version
would fail trying to mutate an immutable selector field.
*/}}
{{- define "devstandards-hub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devstandards-hub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
