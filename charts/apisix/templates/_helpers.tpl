{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "apisix.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "apisix.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "apisix.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "apisix.labels" -}}
helm.sh/chart: {{ include "apisix.chart" . }}
{{ include "apisix.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "apisix.selectorLabels" -}}
{{- if .Values.service.labelsOverride }}
{{- tpl (.Values.service.labelsOverride | toYaml) . }}
{{- else }}
app.kubernetes.io/name: {{ include "apisix.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "apisix.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "apisix.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Renders a value that contains template.
Usage:
{{ include "apisix.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "apisix.tplvalues.render" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}

{{/*
Dynamic Keycloak OIDC/AuthZ plugin config for standalone routes.
Resolves realm from Host subdomain: {tenant}.{rootDomain}
*/}}
{{- define "apisix.dynamicKeycloakAuthPlugin" -}}
dynamic-keycloak-auth:
  root_domain: {{ .Values.global.oidc.rootDomain | quote }}
  keycloak_base_url: {{ .Values.global.oidc.keycloakBaseUrl | quote }}
  use_request_host: false
  keycloak_path: "/auth"
  public_scheme: "https"
  client_id: {{ tpl .Values.global.oidc.clientId . | quote }}
  client_secret: {{ tpl .Values.global.oidc.clientSecret . | quote }}
  bearer_only: true
  token_signing_alg_values_expected: "RS256"
  set_access_token_header: false
  set_userinfo_header: false
  use_jwks: true
  audience: ["cim", "account", "realm-management"]
  required_scopes: ["email", "profile"]
  authz:
    enabled: true
    lazy_load_paths: true
    http_method_as_scope: true
    ssl_verify: false
{{- end -}}

{{- define "apisix.basePluginAttrs" -}}
{{- if .Values.apisix.prometheus.enabled }}
prometheus:
  export_addr:
    ip: 0.0.0.0
    port: {{ .Values.apisix.prometheus.containerPort }}
  export_uri: {{ .Values.apisix.prometheus.path }}
  metric_prefix: {{ .Values.apisix.prometheus.metricPrefix }}
{{- end }}
{{- if .Values.apisix.customPlugins.enabled }}
{{- range $plugin := .Values.apisix.customPlugins.plugins }}
{{- if $plugin.attrs }}
{{ $plugin.name }}: {{- $plugin.attrs | toYaml | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "apisix.pluginAttrs" -}}
{{- merge .Values.apisix.pluginAttrs (include "apisix.basePluginAttrs" . | fromYaml) | toYaml -}}
{{- end -}}

{{/*
Scheme to use while connecting etcd
*/}}
{{- define "apisix.etcd.auth.scheme" -}}
{{- if .Values.etcd.auth.tls.enabled }}
{{- "https" }}
{{- else }}
{{- "http" }}
{{- end }}
{{- end }}

{{/*
Return the name of etcd password secret
*/}}
{{- define "apisix.etcd.secretName" -}}
{{- if and .Values.etcd.enabled .Values.etcd.auth.rbac.create }}
{{- template "common.names.fullname" .Subcharts.etcd }}
{{- else if .Values.externalEtcd.existingSecret }}
{{- print .Values.externalEtcd.existingSecret }}
{{- else if .Values.externalEtcd.user }}
{{- printf "etcd-%s" (include "apisix.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end -}}

{{/*
Return the password key name of etcd secret
*/}}
{{- define "apisix.etcd.secretPasswordKey" -}}
{{- if .Values.etcd.enabled }}
{{- print "etcd-root-password" }}
{{- else }}
{{- print .Values.externalEtcd.secretPasswordKey }}
{{- end }}
{{- end -}}

{{/*
Key to use to fetch admin token from secret
*/}}
{{- define "apisix.admin.credentials.secretAdminKey" -}}
{{- if .Values.apisix.admin.credentials.secretAdminKey }}
{{- .Values.apisix.admin.credentials.secretAdminKey }}
{{- else }}
{{- "admin" }}
{{- end }}
{{- end }}

{{/*
Key to use to fetch viewer token from secret
*/}}
{{- define "apisix.admin.credentials.secretViewerKey" -}}
{{- if .Values.apisix.admin.credentials.secretViewerKey }}
{{- .Values.apisix.admin.credentials.secretViewerKey }}
{{- else }}
{{- "viewer" }}
{{- end }}
{{- end }}
