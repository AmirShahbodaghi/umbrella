{{- define "generic-app.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Service name, taken from .Values.serviceName.
Templates only call this when .Values.serviceName is set;
otherwise they use generic-app.fullname.
*/}}
{{- define "generic-app.serviceName" -}}
{{- .Values.serviceName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-app.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "generic-app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "generic-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- .Release.Name }}
{{- else }}
{{- .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "generic-app.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}