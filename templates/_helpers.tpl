{{/*
_helpers.tpl - Enhanced template helper functions
Production-grade helpers with additional safety checks
*/}}

{{/*
===========================================
NAMING HELPERS
===========================================
*/}}

{{/*
Expand the name of the chart
*/}}
{{- define "consonant-relayer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name
*/}}
{{- define "consonant-relayer.fullname" -}}
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
Create chart name and version
*/}}
{{- define "consonant-relayer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
===========================================
LABEL HELPERS
===========================================
*/}}

{{/*
Common labels
*/}}
{{- define "consonant-relayer.labels" -}}
helm.sh/chart: {{ include "consonant-relayer.chart" . }}
{{ include "consonant-relayer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- if .Values.cluster.environment }}
environment: {{ .Values.cluster.environment }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "consonant-relayer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "consonant-relayer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
===========================================
SERVICE ACCOUNT HELPERS
===========================================
*/}}

{{/*
Create the name of the service account to use
*/}}
{{- define "consonant-relayer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "consonant-relayer.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
===========================================
URL HELPERS
===========================================
*/}}

{{/*
Generate the backend WebSocket URL
*/}}
{{- define "consonant-relayer.backendWsUrl" -}}
{{- if .Values.cloudflare.enabled }}
ws://localhost:8080{{ .Values.backend.socketPath }}
{{- else }}
{{- $url := required "backend.url is required" .Values.backend.url }}
{{- if hasPrefix "https://" $url }}
{{- printf "wss://%s%s" (trimPrefix "https://" $url) .Values.backend.socketPath }}
{{- else if hasPrefix "http://" $url }}
{{- printf "ws://%s%s" (trimPrefix "http://" $url) .Values.backend.socketPath }}
{{- else }}
{{- fail "backend.url must start with http:// or https://" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate OTEL endpoint for KAgent
*/}}
{{- define "consonant-relayer.otelEndpoint" -}}
http://{{ include "consonant-relayer.fullname" . }}.{{ .Release.Namespace }}.svc.cluster.local:{{ .Values.relayer.otel.port }}
{{- end }}

{{/*
===========================================
IMAGE HELPERS
===========================================
*/}}

{{/*
Generate relayer image with digest or tag
*/}}
{{- define "consonant-relayer.relayerImage" -}}
{{- if .Values.relayer.image.digest }}
{{- printf "%s@%s" .Values.relayer.image.repository .Values.relayer.image.digest }}
{{- else }}
{{- $tag := .Values.relayer.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.relayer.image.repository $tag }}
{{- end }}
{{- end }}

{{/*
Generate cloudflared image with digest or tag
*/}}
{{- define "consonant-relayer.cloudflaredImage" -}}
{{- if .Values.cloudflare.sidecar.image.digest }}
{{- printf "%s@%s" .Values.cloudflare.sidecar.image.repository .Values.cloudflare.sidecar.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.cloudflare.sidecar.image.repository .Values.cloudflare.sidecar.image.tag }}
{{- end }}
{{- end }}

{{/*
Generate kubectl image with digest or tag
*/}}
{{- define "consonant-relayer.kubectlImage" -}}
{{- if .Values.hooks.registration.kubectlImage.digest }}
{{- printf "%s@%s" .Values.hooks.registration.kubectlImage.repository .Values.hooks.registration.kubectlImage.digest }}
{{- else }}
{{- printf "%s:%s" .Values.hooks.registration.kubectlImage.repository .Values.hooks.registration.kubectlImage.tag }}
{{- end }}
{{- end }}

{{/*
===========================================
SECRET NAME HELPERS
===========================================
*/}}

{{/*
LLM API key secret name
*/}}
{{- define "consonant-relayer.llmSecretName" -}}
{{- printf "%s-llm" (include "consonant-relayer.fullname" .) }}
{{- end }}

{{/*
Cluster credentials secret name
*/}}
{{- define "consonant-relayer.clusterSecretName" -}}
{{- if .Values.backend.credentials.existingSecret }}
{{- .Values.backend.credentials.existingSecret }}
{{- else }}
{{- printf "%s-cluster" (include "consonant-relayer.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Cloudflare tunnel secret name
*/}}
{{- define "consonant-relayer.tunnelSecretName" -}}
{{- printf "%s-tunnel" (include "consonant-relayer.fullname" .) }}
{{- end }}

{{/*
===========================================
ANNOTATION HELPERS
===========================================
*/}}

{{/*
Common annotations
*/}}
{{- define "consonant-relayer.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Checksum annotation for config
*/}}
{{- define "consonant-relayer.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
Checksum annotation for secrets
*/}}
{{- define "consonant-relayer.secretsChecksum" -}}
checksum/secrets: {{ include (print $.Template.BasePath "/secrets.yaml") . | sha256sum }}
{{- end }}

{{/*
===========================================
KAGENT CONFIGURATION HELPERS
===========================================
*/}}

{{/*
Generate KAgent provider configuration
*/}}
{{- define "consonant-relayer.kagentProvider" -}}
{{- if eq .Values.llm.provider "openai" }}
openAI
{{- else if eq .Values.llm.provider "azureopenai" }}
azureOpenAI
{{- else }}
{{ .Values.llm.provider }}
{{- end }}
{{- end }}

{{/*
===========================================
HELPER UTILITIES
===========================================
*/}}

{{/*
Return true if using external secrets
*/}}
{{- define "consonant-relayer.useExternalSecrets" -}}
{{- if and (eq .Values.secrets.mode "external") .Values.secrets.external.enabled }}
true
{{- end }}
{{- end }}

{{/*
Return the namespace to use
*/}}
{{- define "consonant-relayer.namespace" -}}
{{- default .Release.Namespace .Values.cluster.namespace }}
{{- end }}

{{/*
Return cluster metadata as JSON
*/}}
{{- define "consonant-relayer.clusterMetadata" -}}
{{- $metadata := dict "name" .Values.cluster.name "namespace" (include "consonant-relayer.namespace" .) }}
{{- if .Values.cluster.region }}
{{- $_ := set $metadata "region" .Values.cluster.region }}
{{- end }}
{{- if .Values.cluster.environment }}
{{- $_ := set $metadata "environment" .Values.cluster.environment }}
{{- end }}
{{- if .Values.cluster.metadata }}
{{- $_ := set $metadata "custom" .Values.cluster.metadata }}
{{- end }}
{{- $metadata | toJson }}
{{- end }}