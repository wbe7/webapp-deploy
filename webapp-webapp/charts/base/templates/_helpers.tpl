{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "base.name" -}}
{{- default .Chart.Name .Values.chartName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "base.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if $.Values.fullnameOverride -}}
{{- $.Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Same as base.fullname but $name and .Release.Name are separated by "/"
in case of .Release.Name
*/}}
{{- define "base.fullnameForImage" -}}
{{- if .Values.fullnameForImageOverride -}}
{{- .Values.fullnameForImageOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s/%s" $name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "base.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*  Manage the labels for each entity  */}}
{{- define "base.labels" -}}
app: {{ template "base.name" . }}
fullname: {{ template "base.fullname" . }}
chart: {{ template "base.chart" . }}
release: {{ .Release.Name }}
heritage: {{ .Release.Service }}
{{- range $key, $val := .Values.additionalLabels }}
{{ $key }}: {{ $val | quote }}
{{- end -}}
{{- end -}}

{{/*  Get configMap from file for using from parent chart (note .Values.base.containers)  */}}
{{- define "base.cm.fromfile" -}}
{{- $root := . -}}
{{- range $containerName, $containerValues := .Values.base.containers -}}
{{- range $cm := $containerValues.configMapsFromFiles }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ template "base.fullname" $root }}-{{ $containerName }}-{{ regexReplaceAll "[^a-zA-Z0-9]" (regexReplaceAll "^/" $cm.mountPath "") "-" }}
  labels:
{{ include "base.labels" $root | indent 4 }}
binaryData:
  {{ $cm.fileName }}: {{ $root.Files.Get (printf "files/%s" $cm.fileName) | b64enc }}
{{ end -}}
{{- end -}}
{{- end }}

{{/* Detect if any service is enabled */}}
{{- define "hasServiceMonitor" -}}
  {{- $_hasServiceMonitor := "disabled" -}}
  {{- range $port_name, $port_values := .Values.servicePorts -}}
    {{- if eq (default "disabled" $port_values.serviceMonitor) "enabled" -}}
      {{- $_hasServiceMonitor = "enabled" -}}
    {{- end -}}
  {{- end -}}
  {{- printf $_hasServiceMonitor -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "base.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "base.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Set apiversion for workload resources based on k8s version
*/}}
{{- define "base.k8sVersion" -}}
{{- printf "%s.%s" .Capabilities.KubeVersion.Major (replace "+" "" .Capabilities.KubeVersion.Minor) -}}
{{- end -}}

{{/*
Set Ingress apiVersion based on k8sVersion
*/}}
{{- define "base.ingressApiVersion" -}}
{{- $k8sVersion := include "base.k8sVersion" . -}}
{{- printf "%s" (ternary "networking.k8s.io/v1" "networking.k8s.io/v1beta1" (.Capabilities.APIVersions.Has "networking.k8s.io/v1/Ingress")) -}}
{{- end -}}

{{- define "base.env" -}}
{{- (split "-" .Release.Namespace)._0 -}}
{{- end -}}

{{- define "base.proj" -}}
{{- (split "-" .Release.Namespace)._1 -}}
{{- end -}}

{{- define "secretFile" -}}
vault.hashicorp.com/agent-inject-secret-{{ .secretVault.filename }}: "{{ .project }}/{{ .env }}/{{ .secretVault.subPath }}"
vault.hashicorp.com/secret-volume-path-{{ .secretVault.filename }}: "{{ .secretVault.path }}"
vault.hashicorp.com/agent-inject-template-{{ .secretVault.filename }}: |
  {{`{{ with secret "`}}{{ .project }}/{{ .env }}/{{ .secretVault.subPath }}{{`" -}}
  {{ .Data.`}}{{ .secretVault.keyName }}{{` }}
  {{- end }}`}}
{{- end -}}

{{/*
access_by_lua_block for Ingress-Nginx configuration-snippet

Example:
    nginx.ingress.kubernetes.io/configuration-snippet: |-
      {{ include "gsilib.access_by_lua_block" .Values.smsIngress.https.authTLSVerifyClientRules }}
*/}}
{{- define "gsilib.access_by_lua_block" -}}
access_by_lua_block {
  local function check_dn(dn, rules)
    for k, v in dn do
      if rules[k] and v ~= rules[k] then
        return false
      end
    end
    return true
  end
  local ssl_client_i_dn = string.gmatch(ngx.var.ssl_client_i_dn, "(%w+)=([%w_]+)")
  local ssl_client_s_dn = string.gmatch(ngx.var.ssl_client_s_dn, "(%w+)=([%w_]+)")
  {{- range . }}
  if check_dn(ssl_client_i_dn, {{ include "gsilib.lua_hash" .issuer }}) then
    {{- range .subjects }}
    if check_dn(ssl_client_s_dn, {{ include "gsilib.lua_hash" . }}) then
      ngx.exit(ngx.OK)
    end
    {{- end }}
  end
  {{- end }}
  ngx.exit(ngx.HTTP_FORBIDDEN)
}
{{- end }}

{{/*
Generate Lua "hash" object
*/}}
{{- define "gsilib.lua_hash" -}}
{{"{"}}{{- range $k, $v := . }}{{ $k }}="{{ $v }}",{{- end }}{{"}"}}
{{- end -}}
