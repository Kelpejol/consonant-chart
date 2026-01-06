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
GRPC ENDPOINT HELPERS 
===========================================
*/}}

{{/*
Generate gRPC endpoint from backend URL
This helper derives the gRPC endpoint from backend.url if grpcEndpoint not explicitly set
Supports: https://, http://, grpc:// prefixes
*/}}
{{- define "consonant-relayer.grpcEndpoint" -}}
{{- if .Values.backend.grpcEndpoint }}
{{- .Values.backend.grpcEndpoint }}
{{- else }}
{{- $url := required "backend.url is required" .Values.backend.url }}
{{- if hasPrefix "grpc://" $url }}
{{- $url }}
{{- else if hasPrefix "https://" $url }}
{{- $host := trimPrefix "https://" $url }}
{{- printf "grpc://%s:50051" $host }}
{{- else if hasPrefix "http://" $url }}
{{- $host := trimPrefix "http://" $url }}
{{- printf "grpc://%s:50051" $host }}
{{- else }}
{{- fail "backend.url must start with https://, http://, or grpc://" }}
{{- end }}
{{- end }}
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
Generate OTEL Collector image with digest or tag
*/}}
{{- define "consonant-relayer.otelCollectorImage" -}}
{{- if .Values.otelCollector.image.digest }}
{{- printf "%s@%s" .Values.otelCollector.image.repository .Values.otelCollector.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.otelCollector.image.repository .Values.otelCollector.image.tag }}
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
Auth bearer token secret name (for pre-install hook)
*/}}
{{- define "consonant-relayer.authSecretName" -}}
{{- if .Values.auth.existingSecret.enabled }}
{{- .Values.auth.existingSecret.name }}
{{- else }}
{{- printf "%s-auth" (include "consonant-relayer.fullname" .) }}
{{- end }}
{{- end }}

{{/*
LLM API key secret name
*/}}
{{- define "consonant-relayer.llmSecretName" -}}
{{- printf "%s-llm" (include "consonant-relayer.fullname" .) }}
{{- end }}

{{/*
Cluster credentials secret name
Contains cluster_id and cluster_token (NOT bearer token)
Created by pre-install hook
*/}}
{{- define "consonant-relayer.clusterSecretName" -}}
{{- if .Values.backend.credentials.existingSecret }}
{{- .Values.backend.credentials.existingSecret }}
{{- else }}
{{- printf "%s-cluster" (include "consonant-relayer.fullname" .) }}
{{- end }}
{{- end }}


{{/*

===========================================
OTEL COLLECTOR HELPERS (NEW)
===========================================
*/}}

{{/*
OTEL Collector endpoint for KAgent
Returns the internal cluster endpoint for OTEL Collector
*/}}
{{- define "consonant-relayer.otelCollectorEndpoint" -}}
{{- if .Values.kagent.otelEndpoint }}
{{- .Values.kagent.otelEndpoint }}
{{- else }}
{{- printf "http://%s-otel:4317" (include "consonant-relayer.fullname" .) }}
{{- end }}
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
{{/*
===========================================
VALIDATION HELPERS
===========================================
*/}}

{{/*
Validate required values
Run comprehensive validation before rendering any resources
*/}}
{{- define "consonant-relayer.validateConfig" -}}
{{- $requiredValues := list
  "cluster.name"
  "backend.url"
-}}
{{- range $requiredValues }}
{{- if not (index $.Values (split "." . | first) | default dict | dig (split "." . | rest | join ".") "" ) }}
{{- fail (printf "ERROR: %s is required" .) }}
{{- end }}
{{- end }}

{{/*
Validate cluster name format (DNS-1123)
*/}}
{{- if .Values.cluster.name }}
{{- if not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" .Values.cluster.name) }}
{{- fail (printf "ERROR: cluster.name '%s' must be DNS-1123 compliant (lowercase, alphanumeric, hyphens)" .Values.cluster.name) }}
{{- end }}
{{- if or (lt (len .Values.cluster.name) 3) (gt (len .Values.cluster.name) 63) }}
{{- fail (printf "ERROR: cluster.name must be 3-63 characters long (current: %d)" (len .Values.cluster.name)) }}
{{- end }}
{{- end }}

{{/*
Validate backend URL format
*/}}
{{- if .Values.backend.url }}
{{- if not (regexMatch "^(https?|grpc)://.+" .Values.backend.url) }}
{{- fail "ERROR: backend.url must start with https://, http://, or grpc://" }}
{{- end }}
{{- end }}

{{/*
Validate authentication configuration
*/}}
{{- if not (or .Values.auth.bearerToken .Values.auth.existingSecret.enabled (and (eq .Values.secrets.mode "external") .Values.secrets.external.enabled)) }}
{{- fail "ERROR: auth.bearerToken is required OR auth.existingSecret.enabled=true OR secrets.mode=external with secrets.external.enabled=true" }}
{{- end }}

{{- end }}