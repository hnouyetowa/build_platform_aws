{{/*
Expand the name of the chart.
*/}}
{{- define "petclinic-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "petclinic-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels applied to every resource
*/}}
{{- define "petclinic-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels used by Service and Deployment
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.fullname" . }}
{{- end }}
