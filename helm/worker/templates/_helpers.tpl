{{- define "worker.fullname" -}}
{{ .Release.Name }}-worker
{{- end -}}

{{- define "worker.labels" -}}
app.kubernetes.io/name: worker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* env block extracted into a helper because BOTH the Deployment and the CronJob need the exact same env vars; define once, include twice */}}
{{/* `| quote` wraps values in double-quotes in the rendered YAML — prevents YAML parsing issues if a value contains colons or special chars */}}
{{/* POSTGRES_PASSWORD uses valueFrom/secretKeyRef: the password is NOT inlined in the Deployment spec; Kubernetes fetches it from the Secret at runtime */}}
{{- define "worker.env" -}}
- name: POSTGRES_HOST
  value: {{ .Values.env.postgresHost | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.env.postgresPort | quote }}
- name: POSTGRES_DB
  value: {{ .Values.env.postgresDb | quote }}
- name: POSTGRES_USER
  value: {{ .Values.env.postgresUser | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresSecretName }}
      key: {{ .Values.postgresSecretKey }}
- name: REDIS_HOST
  value: {{ .Values.env.redisHost | quote }}
- name: REDIS_PORT
  value: {{ .Values.env.redisPort | quote }}
- name: REDIS_QUEUE_NAME
  value: {{ .Values.env.redisQueueName | quote }}
- name: RESULTS_DIR
  value: {{ .Values.env.resultsDir | quote }}
{{- end -}}
