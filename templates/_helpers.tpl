{{/*
_helpers.tpl - Reusable template functions
These are Go template functions that generate YAML snippets
Used across multiple template files to avoid repetition

NAMING CONVENTION:
- All helpers are prefixed with chart name: consonant-relayer
- Format: {{ include "consonant-relayer.functionName" . }}
- The dot (.) passes the entire context to the function
*/}}

{{/*
===========================================
NAMING HELPERS
===========================================
*/}}

{{/*
Expand the name of the chart
Returns: "consonant-relayer"
Usage: {{ include "consonant-relayer.name" . }}

Logic:
1. If nameOverride is set, use it
2. Otherwise use Chart.Name
3. Truncate to 63 chars (K8s label limit)
4. Remove trailing hyphens
*/}}
{{- define "consonant-relayer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name
Combines release name + chart name for uniqueness
Returns: "my-release-consonant-relayer"
Usage: {{ include "consonant-relayer.fullname" . }}

Logic:
1. If fullnameOverride is set, use it
2. If release name contains chart name, use release name
3. Otherwise combine: release-name-chart-name
4. Truncate to 63 chars, remove trailing hyphens

Examples:
- helm install prod consonant-relayer → "prod-consonant-relayer"
- helm install consonant-relayer consonant-relayer → "consonant-relayer"
- helm install my-app consonant-relayer → "my-app-consonant-relayer"
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
Create chart name and version as used by the chart label
Returns: "consonant-relayer-1.0.0"
Usage: {{ include "consonant-relayer.chart" . }}

Used in: helm.sh/chart label
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
Common labels applied to ALL resources
These labels are used for:
- Resource organization in kubectl
- Selector matching
- Monitoring/alerting queries
- Helm upgrade/rollback tracking

Returns:
  helm.sh/chart: consonant-relayer-1.0.0
  app.kubernetes.io/name: consonant-relayer
  app.kubernetes.io/instance: my-release
  app.kubernetes.io/version: "1.0.0"
  app.kubernetes.io/managed-by: Helm

Usage: {{ include "consonant-relayer.labels" . | nindent 4 }}

NOTE: nindent 4 adds 4 spaces of indentation
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
{{- end }}

{{/*
Selector labels for pod matching
These MUST BE IMMUTABLE between upgrades
Used in: Deployment.spec.selector.matchLabels, Service.spec.selector

Returns:
  app.kubernetes.io/name: consonant-relayer
  app.kubernetes.io/instance: my-release

Usage: {{ include "consonant-relayer.selectorLabels" . | nindent 6 }}

WARNING: Changing these will cause Helm upgrade to fail
Deployments cannot change their selector after creation
*/}}
{{- define "consonant-relayer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "consonant-relayer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
===========================================
SERVICEACCOUNT HELPERS
===========================================
*/}}

{{/*
Create the name of the service account to use
Returns: Either custom name or generated name
Usage: {{ include "consonant-relayer.serviceAccountName" . }}

Logic:
1. If serviceAccount.create is true:
   - Use serviceAccount.name if set
   - Otherwise generate from fullname
2. If serviceAccount.create is false:
   - Use serviceAccount.name if set
   - Otherwise use "default" (K8s default SA)
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
Handles both Cloudflare tunnel and direct connection

Returns:
- If cloudflare.enabled: "ws://localhost:8080" (connects through sidecar)
- If not: transforms backend.url to WebSocket URL

Logic for direct connection:
1. Replace https:// with wss://
2. Replace http:// with ws://
3. Append socketPath

Usage: {{ include "consonant-relayer.backendWsUrl" . }}

Examples:
- cloudflare.enabled: ws://localhost:8080
- backend.url=https://api.example.com: wss://api.example.com/socket.io
- backend.url=http://api.example.com: ws://api.example.com/socket.io
*/}}
{{- define "consonant-relayer.backendWsUrl" -}}
{{- if .Values.cloudflare.enabled }}
ws://localhost:8080{{ .Values.backend.socketPath }}
{{- else }}
{{- $url := required "backend.url is required when cloudflare.enabled is false" .Values.backend.url }}
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
Points to the relayer service

Returns: http://my-release-consonant-relayer:4317

Usage: {{ include "consonant-relayer.otelEndpoint" . }}
*/}}
{{- define "consonant-relayer.otelEndpoint" -}}
http://{{ include "consonant-relayer.fullname" . }}:{{ .Values.relayer.otel.port }}
{{- end }}

{{/*
===========================================
IMAGE HELPERS
===========================================
*/}}

{{/*
Generate relayer image name with tag
Returns: ghcr.io/consonant/relayer:1.0.0

Usage: {{ include "consonant-relayer.relayerImage" . }}

Logic:
1. Use relayer.image.tag if set
2. Otherwise use Chart.appVersion
3. Combine with repository
*/}}
{{- define "consonant-relayer.relayerImage" -}}
{{- $tag := .Values.relayer.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.relayer.image.repository $tag }}
{{- end }}

{{/*
Generate cloudflared image name with tag
Returns: cloudflare/cloudflared:latest

Usage: {{ include "consonant-relayer.cloudflaredImage" . }}
*/}}
{{- define "consonant-relayer.cloudflaredImage" -}}
{{- printf "%s:%s" .Values.cloudflare.sidecar.image.repository .Values.cloudflare.sidecar.image.tag }}
{{- end }}

{{/*
===========================================
VALIDATION HELPERS
===========================================
*/}}

{{/*
Validate required values before rendering templates
This ensures the chart fails fast with clear error messages

Usage: {{ include "consonant-relayer.validateValues" . }}

Checks:
1. cluster.name is set
2. backend.url is set (if not using tunnel)
3. cloudflare.tunnelToken is set (if using tunnel)
4. llm.apiKey is set

Each check uses Helm's required function which:
- Fails template rendering if value is empty
- Shows custom error message
*/}}
{{- define "consonant-relayer.validateValues" -}}
{{- if not .Values.cluster.name }}
  {{- fail "ERROR: cluster.name is required. Set it with: --set cluster.name=my-cluster" }}
{{- end }}
{{- if and (not .Values.cloudflare.enabled) (not .Values.backend.url) }}
  {{- fail "ERROR: backend.url is required when cloudflare.enabled is false. Set it with: --set backend.url=https://..." }}
{{- end }}
{{- if and .Values.cloudflare.enabled (not .Values.cloudflare.tunnelToken) }}
  {{- fail "ERROR: cloudflare.tunnelToken is required when cloudflare.enabled is true. Get your token from: Cloudflare Dashboard → Zero Trust → Access → Tunnels. Set it with: --set cloudflare.tunnelToken=eyJ..." }}
{{- end }}
{{- if not .Values.llm.apiKey }}
  {{- fail "ERROR: llm.apiKey is required for KAgent. Set it with: --set llm.apiKey=sk-..." }}
{{- end }}
{{- end }}

{{/*
===========================================
SECRET NAME HELPERS
===========================================
*/}}

{{/*
Generate name for LLM API key secret
Returns: my-release-consonant-relayer-llm

Usage: {{ include "consonant-relayer.llmSecretName" . }}
*/}}
{{- define "consonant-relayer.llmSecretName" -}}
{{ include "consonant-relayer.fullname" . }}-llm
{{- end }}

{{/*
Generate name for cluster credentials secret
Created by pre-install hook
Returns: my-release-consonant-relayer-cluster

Usage: {{ include "consonant-relayer.clusterSecretName" . }}
*/}}
{{- define "consonant-relayer.clusterSecretName" -}}
{{ include "consonant-relayer.fullname" . }}-cluster
{{- end }}

{{/*
Generate name for Cloudflare tunnel secret
Returns: my-release-consonant-relayer-tunnel

Usage: {{ include "consonant-relayer.tunnelSecretName" . }}
*/}}
{{- define "consonant-relayer.tunnelSecretName" -}}
{{ include "consonant-relayer.fullname" . }}-tunnel
{{- end }}

{{/*
===========================================
ANNOTATION HELPERS
===========================================
*/}}

{{/*
Generate common annotations
Merges chart-level and user-provided annotations

Usage: {{ include "consonant-relayer.annotations" . | nindent 4 }}
*/}}
{{- define "consonant-relayer.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Generate checksum annotation for config
Used to force pod restart when ConfigMap changes

Returns: checksum/config: <sha256-hash>

Usage in pod template annotations:
  annotations:
    {{ include "consonant-relayer.configChecksum" . | nindent 8 }}

How it works:
1. Includes the configmap.yaml template
2. Computes SHA256 hash of the content
3. Returns as annotation
4. K8s sees annotation change → triggers rolling update
*/}}
{{- define "consonant-relayer.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}

{{/*
===========================================
KAGENT CONFIGURATION HELPERS
===========================================
*/}}

{{/*
Generate KAgent provider configuration
Maps our llm.provider to KAgent's provider format

Returns the provider name in KAgent format
Usage: {{ include "consonant-relayer.kagentProvider" . }}

Mappings:
- openai → openAI
- anthropic → anthropic
- gemini → gemini
- azureopenai → azureOpenAI
- ollama → ollama
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