{{/* define starts a named template block; "api.fullname" is its name; reusable anywhere in this chart with `include` */}}
{{- define "api.fullname" -}}
{{/* .Release.Name = the name given at install time, e.g. `helm install myrelease ./api` → "myrelease-api"; keeps names unique if you install the chart twice */}}
{{ .Release.Name }}-api
{{- end -}}

{{/* reusable label block; included in metadata.labels and selector.matchLabels of every resource in this chart */}}
{{- define "api.labels" -}}
{{/* well-known Kubernetes label: identifies the application name; used by tooling like Helm, Lens, k9s */}}
app.kubernetes.io/name: api
{{/* identifies the specific Helm release instance; lets you have multiple installs of the same chart in one cluster without label collisions */}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
