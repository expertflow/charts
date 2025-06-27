{{/* vim: set filetype=mustache: */}}
{{/*
Renders a merged list of environment variables suitable for a container's 'env:' block.
It takes a default list and an override list, merges them based on the 'name' key,
giving precedence to variables defined in the override list.
It uses 'common.tplvalues.render' to render potential Go template syntax within values.

Example Usage in deployment.yaml (indented appropriately):
env: {{- include "mychart.helpers.mergedEnvVars" (dict "context" $ "defaultList" .Values.extraEnvVars "overrideList" .Values.siteEnvVars) | nindent 10 }}

Expected input via 'dict':
{
  "context": $,      # The top-level Helm template context
  "defaultList": [], # The list from .Values.extraEnvVars (chart defaults)
  "overrideList": [] # The list from .Values.siteEnvVars (user values)
}
*/}}
{{- define "ef.helpers.mergedEnvVars" -}}
  {{- $context := .context -}}
  {{- $defaultList := .defaultList | default list -}}
  {{- $overrideList := .overrideList | default list -}}
  {{- $envMap := dict }}

  {{- range $defaultList }}
    {{- if .name }}
      {{- $_ := set $envMap .name . }}
    {{- else }}
      {{- fail (printf "Default environment variable in 'extraEnvVars' missing 'name' field: %s" (toJson .)) }}
    {{- end }}
  {{- end }}

  {{- range $overrideList }}
    {{- if .name }}
      {{- $_ := set $envMap .name . }}
    {{- else }}
      {{- fail (printf "Environment variable in 'siteEnvVars' missing 'name' field: %s" (toJson .)) }}
    {{- end }}
  {{- end }}

  {{- range $name, $envVar := $envMap }}
  - name: {{ $name | quote }}
    {{- /* Render value OR valueFrom, prioritizing value if both somehow exist */}}
    {{- $value := get $envVar "value" }}
    {{- $valueFrom := get $envVar "valueFrom" }}
    {{- if not (eq $value nil) }}
    value: {{ include "common.tplvalues.render" (dict "value" $value "context" $context) | quote }}
    {{- else if $valueFrom }}
    valueFrom: {{- include "common.tplvalues.render" (dict "value" $valueFrom "context" $context) | nindent 6 }}
    {{- else }}
    # value: "" # Handle empty value if needed
    {{- end }}
  {{- end }}
{{- end -}}
