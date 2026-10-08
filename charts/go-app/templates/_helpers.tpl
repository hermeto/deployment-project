{{/*
Chart name, overridable with nameOverride.
*/}}
{{- define "go-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified name: fullnameOverride, or the release name suffixed with the chart name unless it already
contains it (release "go-app" -> "go-app", release "dev" -> "dev-go-app").
*/}}
{{- define "go-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label value.
*/}}
{{- define "go-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels: immutable once the Deployment exists, so they never include the version.
*/}}
{{- define "go-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "go-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels, applied to every resource.
*/}}
{{- define "go-app.labels" -}}
helm.sh/chart: {{ include "go-app.chart" . }}
{{ include "go-app.selectorLabels" . }}
app.kubernetes.io/version: {{ include "go-app.version" . | quote }}
app.kubernetes.io/component: web
app.kubernetes.io/part-of: go-app
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Application version: the image tag, or the chart appVersion.
*/}}
{{- define "go-app.version" -}}
{{- default .Chart.AppVersion .Values.image.tag | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Container image reference: repository@digest when a digest is set, repository:tag otherwise.
*/}}
{{- define "go-app.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "go-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "go-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Cross-field validation that the JSON schema cannot express.
*/}}
{{- define "go-app.validate" -}}
{{- if and .Values.autoscaling.enabled (gt (int .Values.autoscaling.minReplicas) (int .Values.autoscaling.maxReplicas)) }}
{{- fail (printf "autoscaling.minReplicas (%d) must not be greater than autoscaling.maxReplicas (%d)" (int .Values.autoscaling.minReplicas) (int .Values.autoscaling.maxReplicas)) }}
{{- end }}
{{- if and .Values.autoscaling.enabled (not (dig "requests" "cpu" "" .Values.resources)) .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- fail "autoscaling on CPU utilization requires resources.requests.cpu" }}
{{- end }}
{{- if and .Values.autoscaling.enabled (not (dig "requests" "memory" "" .Values.resources)) .Values.autoscaling.targetMemoryUtilizationPercentage }}
{{- fail "autoscaling on memory utilization requires resources.requests.memory" }}
{{- end }}
{{- end }}
