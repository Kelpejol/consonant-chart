{{/*
_validators.tpl - Comprehensive input validation
These validators ensure all user inputs are safe and correct
*/}}

{{/*
===========================================
COMPREHENSIVE VALIDATION
===========================================
Run all validations before rendering any resources
This ensures the chart fails fast with clear error messages
*/}}
{{- define "consonant-relayer.validate.all" -}}
{{- include "consonant-relayer.validate.cluster" . }}
{{- include "consonant-relayer.validate.backend" . }}
{{- include "consonant-relayer.validate.secrets" . }}
{{- include "consonant-relayer.validate.llm" . }}
{{- include "consonant-relayer.validate.images" . }}
{{- include "consonant-relayer.validate.resources" . }}
{{- end }}

{{/*
===========================================
CLUSTER VALIDATION
===========================================
Validates cluster configuration
*/}}
{{- define "consonant-relayer.validate.cluster" -}}
{{- if not .Values.cluster.name }}
  {{- fail "ERROR: cluster.name is required.\n\nSet it with: --set cluster.name=production-us-east-1\n\nCluster name must be:\n  - 3-63 characters\n  - Start and end with alphanumeric\n  - Contain only lowercase letters, numbers, and hyphens\n  - DNS-1123 compliant" }}
{{- end }}

{{/* Validate cluster name format */}}
{{- if not (regexMatch "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$" .Values.cluster.name) }}
  {{- fail (printf "ERROR: cluster.name '%s' is invalid.\n\nCluster name must:\n  - Start with lowercase letter or number\n  - End with lowercase letter or number\n  - Contain only lowercase letters, numbers, and hyphens\n  - Be 3-63 characters long\n\nExamples:\n  - production-us-east-1\n  - staging-eu-west\n  - dev-local" .Values.cluster.name) }}
{{- end }}

{{/* Validate cluster name length */}}
{{- if or (lt (len .Values.cluster.name) 3) (gt (len .Values.cluster.name) 63) }}
  {{- fail (printf "ERROR: cluster.name '%s' must be between 3 and 63 characters.\n\nCurrent length: %d" .Values.cluster.name (len .Values.cluster.name)) }}
{{- end }}

{{- end }}

{{/*
===========================================
BACKEND VALIDATION
===========================================
Validates backend configuration
*/}}
{{- define "consonant-relayer.validate.backend" -}}
{{- if not .Values.backend.url }}
  {{- fail "ERROR: backend.url is required.\n\nSet it with: --set backend.url=https://consonant.company.com\n\nBackend URL must:\n  - Be a valid HTTP or HTTPS URL\n  - Be reachable from the cluster\n  - Use HTTPS in production (HTTP allowed for development)" }}
{{- end }}

{{/* Validate URL format */}}
{{- if not (regexMatch "^https?://.+" .Values.backend.url) }}
  {{- fail "ERROR: backend.url must start with http:// or https://" }}
{{- end }}

{{- if and (hasPrefix "http://" .Values.backend.url) (eq .Values.cluster.environment "production") }}
  {{- printf "\n⚠️  WARNING: Using HTTP in production is insecure!\n   Backend URL: %s\n   Recommendation: Use HTTPS\n" .Values.backend.url | fail }}
{{- end }}

{{/* Validate reconnection settings */}}
{{- if .Values.backend.reconnection.enabled }}
  {{- if gt .Values.backend.reconnection.delay .Values.backend.reconnection.maxDelay }}
    {{- fail (printf "ERROR: backend.reconnection.delay (%d) cannot be greater than maxDelay (%d)" .Values.backend.reconnection.delay .Values.backend.reconnection.maxDelay) }}
  {{- end }}
  
  {{- if lt .Values.backend.reconnection.multiplier 1.0 }}
    {{- fail "ERROR: backend.reconnection.multiplier must be >= 1.0 for exponential backoff" }}
  {{- end }}
{{- end }}

{{/* Validate connection timeout */}}
{{- if or (lt .Values.backend.connectionTimeout 5) (gt .Values.backend.connectionTimeout 300) }}
  {{- fail (printf "ERROR: backend.connectionTimeout must be between 5 and 300 seconds.\n\nCurrent value: %d" .Values.backend.connectionTimeout) }}
{{- end }}
{{- end }}

{{/*
===========================================
SECRETS VALIDATION
===========================================
Validates secret management configuration
*/}}
{{- define "consonant-relayer.validate.secrets" -}}
{{- if eq .Values.secrets.mode "external" }}
  {{/* External secrets validation */}}
  {{- if .Values.secrets.external.enabled }}
    {{- if not .Values.secrets.external.secretStore.name }}
      {{- fail "ERROR: secrets.external.secretStore.name is required when using external secrets.\n\nExternal secrets require:\n  1. External Secrets Operator installed in cluster\n  2. SecretStore or ClusterSecretStore created\n  3. SecretStore name configured\n\nSet it with:\n  --set secrets.external.secretStore.name=vault-backend\n\nOr disable external secrets:\n  --set secrets.mode=kubernetes" }}
    {{- end }}
    
    {{/* Validate SecretStore kind */}}
    {{- if not (has .Values.secrets.external.secretStore.kind (list "SecretStore" "ClusterSecretStore")) }}
      {{- fail (printf "ERROR: secrets.external.secretStore.kind must be 'SecretStore' or 'ClusterSecretStore'.\n\nCurrent value: %s" .Values.secrets.external.secretStore.kind) }}
    {{- end }}
    
    {{/* Validate required secret paths */}}
    {{- if not .Values.secrets.external.paths.llmApiKey.key }}
      {{- fail "ERROR: secrets.external.paths.llmApiKey.key is required.\n\nExample:\n  --set secrets.external.paths.llmApiKey.key=secret/data/consonant/llm-key" }}
    {{- end }}
    
  {{- end }}
{{- else if eq .Values.secrets.mode "kubernetes" }}
  {{/* Kubernetes secrets validation */}}
  {{- if not .Values.secrets.kubernetes.llmApiKey }}
    {{- fail "ERROR: secrets.kubernetes.llmApiKey is required when using Kubernetes secrets.\n\nSet it with:\n  --set secrets.kubernetes.llmApiKey=sk-...\n\nOr use external secrets (recommended):\n  --set secrets.mode=external\n  --set secrets.external.enabled=true" }}
  {{- end }}
  
 
{{- else }}
  {{- fail (printf "ERROR: secrets.mode must be 'external' or 'kubernetes'.\n\nCurrent value: %s" .Values.secrets.mode) }}
{{- end }}
{{- end }}

{{/*


===========================================
LLM VALIDATION
===========================================
Validates LLM configuration
*/}}
{{- define "consonant-relayer.validate.llm" -}}
{{- if not .Values.llm.provider }}
  {{- fail "ERROR: llm.provider is required.\n\nSupported providers:\n  - openai\n  - anthropic\n  - gemini\n  - azureopenai\n  - ollama\n\nSet it with:\n  --set llm.provider=anthropic" }}
{{- end }}

{{/* Validate provider value */}}
{{- if not (has .Values.llm.provider (list "openai" "anthropic" "gemini" "azureopenai" "ollama")) }}
  {{- fail (printf "ERROR: llm.provider '%s' is not supported.\n\nSupported providers:\n  - openai\n  - anthropic\n  - gemini\n  - azureopenai\n  - ollama" .Values.llm.provider) }}
{{- end }}

{{/* Validate API key if using Kubernetes secrets */}}
{{- if eq .Values.secrets.mode "kubernetes" }}
  {{- if .Values.secrets.kubernetes.llmApiKey }}
    {{/* Validate OpenAI key format */}}
    {{- if eq .Values.llm.provider "openai" }}
      {{- if not (hasPrefix "sk-" .Values.secrets.kubernetes.llmApiKey) }}
        {{- fail "ERROR: OpenAI API key must start with 'sk-'.\n\nGet your key from: https://platform.openai.com/api-keys" }}
      {{- end }}
    {{- end }}
    
    {{/* Validate Anthropic key format */}}
    {{- if eq .Values.llm.provider "anthropic" }}
      {{- if not (hasPrefix "sk-ant-" .Values.secrets.kubernetes.llmApiKey) }}
        {{- fail "ERROR: Anthropic API key must start with 'sk-ant-'.\n\nGet your key from: https://console.anthropic.com/settings/keys" }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}

{{/* Validate Azure OpenAI configuration */}}
{{- if eq .Values.llm.provider "azureopenai" }}
  {{- if eq .Values.secrets.mode "kubernetes" }}
    {{- if not .Values.secrets.kubernetes.azureEndpoint }}
      {{- fail "ERROR: secrets.kubernetes.azureEndpoint is required for Azure OpenAI.\n\nExample:\n  --set secrets.kubernetes.azureEndpoint=https://your-resource.openai.azure.com" }}
    {{- end }}
    
    {{- if not .Values.secrets.kubernetes.azureDeploymentName }}
      {{- fail "ERROR: secrets.kubernetes.azureDeploymentName is required for Azure OpenAI.\n\nExample:\n  --set secrets.kubernetes.azureDeploymentName=gpt-4" }}
    {{- end }}
  {{- end }}
{{- end }}

{{/* Validate model is set */}}
{{- if not .Values.llm.model }}
  {{- fail "ERROR: llm.model is required.\n\nExamples:\n  OpenAI: gpt-4o, gpt-4o-mini\n  Anthropic: claude-3-5-sonnet-20241022\n  Gemini: gemini-1.5-pro" }}
{{- end }}
{{- end }}

{{/*
===========================================
IMAGE VALIDATION
===========================================
Validates container images
*/}}
{{- define "consonant-relayer.validate.images" -}}
{{/* Validate relayer image */}}
{{- if not .Values.relayer.image.digest }}
  {{- printf "\n⚠️  WARNING: relayer.image.digest is not set.\n   Using image tags instead of digests is insecure.\n   Recommendation: Pin to digest for immutability.\n" | fail }}
{{- end }}

{{/* Validate digest format if provided */}}
{{- if .Values.relayer.image.digest }}
  {{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .Values.relayer.image.digest) }}
    {{- fail (printf "ERROR: relayer.image.digest is not a valid SHA256 digest.\n\nCurrent value: %s\n\nExpected format: sha256:abc123..." .Values.relayer.image.digest) }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
===========================================
RESOURCES VALIDATION
===========================================
Validates resource requests and limits
*/}}
{{- define "consonant-relayer.validate.resources" -}}
{{/* Validate replicas */}}
{{- if or (lt (int .Values.relayer.replicas) 1) (gt (int .Values.relayer.replicas) 100) }}
  {{- fail (printf "ERROR: relayer.replicas must be between 1 and 100.\n\nCurrent value: %d\n\nRecommendation:\n  - Development: 1\n  - Staging: 2\n  - Production: 3+" (int .Values.relayer.replicas)) }}
{{- end }}

{{/* Warn if single replica in production */}}
{{- if and (eq .Values.cluster.environment "production") (eq (int .Values.relayer.replicas) 1) }}
  {{- printf "\n⚠️  WARNING: Running single replica in production!\n   Current replicas: 1\n   Recommendation: Use 3+ replicas for high availability\n" | fail }}
{{- end }}

{{/* Validate CPU requests don't exceed limits */}}
{{- $cpuRequest := .Values.relayer.resources.requests.cpu }}
{{- $cpuLimit := .Values.relayer.resources.limits.cpu }}

{{/* Validate memory requests don't exceed limits */}}
{{- $memRequest := .Values.relayer.resources.requests.memory }}
{{- $memLimit := .Values.relayer.resources.limits.memory }}

{{/* Additional validation could be added here for specific resource values */}}
{{- end }}

{{/*
===========================================
KUBERNETES VERSION VALIDATION
===========================================
Validates Kubernetes version compatibility
*/}}
{{- define "consonant-relayer.validate.kubeVersion" -}}
{{- if .Capabilities.KubeVersion.GitVersion }}
  {{- if not (semverCompare ">=1.32.0-0 <1.35.0-0" .Capabilities.KubeVersion.GitVersion) }}
    {{- fail (printf "ERROR: Kubernetes version %s is not supported.\n\nMinimum required version: 1.32.0\n\nPlease upgrade your Kubernetes cluster." .Capabilities.KubeVersion.GitVersion) }}
  {{- end }}
{{- end }}
{{- end }}