{{- define "hermes-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.labels" -}}
helm.sh/chart: {{ include "hermes-agent.chart" . }}
{{ include "hermes-agent.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: hermes-agent
{{- end -}}

{{- define "hermes-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hermes-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "hermes-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "hermes-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.configMapName" -}}
{{- printf "%s-config" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.bootstrapConfigMapName" -}}
{{- if .Values.bootstrap.existingConfigMap -}}
{{- .Values.bootstrap.existingConfigMap -}}
{{- else -}}
{{- include "hermes-agent.configMapName" . -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.pvcName" -}}
{{- printf "%s-data" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.defaultExposedPorts" -}}
{{- $ports := list -}}
{{- if .Values.apiServer.enabled -}}
{{- $ports = append $ports (dict "name" "api-server" "port" (int .Values.apiServer.port) "targetPort" (int .Values.apiServer.port) "containerPort" (int .Values.apiServer.port) "protocol" "TCP" "appProtocol" "http") -}}
{{- end -}}
{{- if .Values.webhook.enabled -}}
{{- $ports = append $ports (dict "name" "webhook" "port" (int .Values.webhook.port) "targetPort" (int .Values.webhook.port) "containerPort" (int .Values.webhook.port) "protocol" "TCP" "appProtocol" "http") -}}
{{- end -}}
{{- if .Values.telegramWebhook.enabled -}}
{{- $ports = append $ports (dict "name" "telegram-webhook" "port" (int .Values.telegramWebhook.port) "targetPort" (int .Values.telegramWebhook.port) "containerPort" (int .Values.telegramWebhook.port) "protocol" "TCP" "appProtocol" "https") -}}
{{- end -}}
{{- toYaml $ports -}}
{{- end -}}

{{- define "hermes-agent.effectiveServicePorts" -}}
{{- if gt (len .Values.service.ports) 0 -}}
{{- toYaml .Values.service.ports -}}
{{- else -}}
{{- include "hermes-agent.defaultExposedPorts" . -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.primaryServicePortNumber" -}}
{{- $ports := include "hermes-agent.effectiveServicePorts" . | fromYamlArray -}}
{{- if and .Values.service.enabled (gt (len $ports) 0) -}}
{{- (index $ports 0).port -}}
{{- else -}}
{{- fail "service.enabled=true with at least one effective service port is required for ingress or virtualService routing" -}}
{{- end -}}
{{- end -}}
