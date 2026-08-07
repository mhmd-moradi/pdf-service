{{- define "worker.fullname" -}}
{{ .Release.Name }}-worker
{{- end -}}

{{- define "worker.labels" -}}
app.kubernetes.io/name: worker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* env block extracted into a helper because BOTH the Deployment and the CronJob need the exact same env vars; define once, include twice */}}
{{- define "worker.env" -}}
- name: POSTGRES_HOST
{{/* `| quote` wraps the value in double-quotes in the rendered YAML — prevents YAML parsing issues if the value contains colons or special chars */}}
  value: {{ .Values.env.postgresHost | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.env.postgresPort | quote }}
- name: POSTGRES_DB
  value: {{ .Values.env.postgresDb | quote }}
- name: POSTGRES_USER
  value: {{ .Values.env.postgresUser | quote }}
- name: POSTGRES_PASSWORD
{{/* valueFrom instead of value: the password is NOT inlined in the Deployment spec; Kubernetes fetches it from the Secret at runtime */}}
  valueFrom:
    secretKeyRef:
{{/* name of the Secret object to read from */}}
      name: {{ .Values.postgresSecretName }}
{{/* key inside that Secret's data map */}}
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
