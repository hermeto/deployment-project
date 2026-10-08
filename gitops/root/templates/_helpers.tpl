{{/*
Labels shared by every object of the root chart.
*/}}
{{- define "root.labels" -}}
app.kubernetes.io/part-of: gitops
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Retry policy shared by every Application: transient sync failures are retried with backoff.
*/}}
{{- define "root.retry" -}}
retry:
  limit: 5
  backoff:
    duration: 10s
    factor: 2
    maxDuration: 3m
{{- end }}
