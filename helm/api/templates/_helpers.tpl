{{/* define starts a named template block; "api.fullname" is its name; reusable anywhere in this chart with `include` */}}
{{/* .Release.Name = the name given at install time, e.g. `helm install myrelease ./api` → "myrelease-api"; keeps names unique if you install the chart twice */}}
{{- define "api.fullname" -}}
{{ .Release.Name }}-api
{{- end -}}

{{/* reusable label block; included in metadata.labels and selector.matchLabels of every resource in this chart */}}
{{/* well-known Kubernetes labels: name identifies the app; instance identifies the specific Helm release (allows multiple installs in the same cluster without label collisions) */}}
{{- define "api.labels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
