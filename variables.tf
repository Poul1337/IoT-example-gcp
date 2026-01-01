variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "iot-proj-482921"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "europe-west1-b"
}

variable "network_name" {
  description = "VPC Network name"
  type        = string
  default     = "emqx-network"
}

variable "emqx_machine_type" {
  description = "Machine type for EMQX instances"
  type        = string
  default     = "e2-medium"
}

variable "emqx_instance_count" {
  description = "Number of EMQX instances"
  type        = number
  default     = 1
}

variable "mqtt_port" {
  description = "MQTT broker port"
  type        = number
  default     = 8883
}

variable "ws_port" {
  description = "WebSocket port (alternative for dev)"
  type        = number
  default     = 8083
}

variable "dashboard_port" {
  description = "EMQX Dashboard port"
  type        = number
  default     = 18083
}

variable "mqtts_dev_port" {
  description = "MQTTS port for dev environment"
  type        = number
  default     = 8884
}

variable "mqtts_prod_port" {
  description = "MQTTS port for prod environment"
  type        = number
  default     = 8883
}

variable "emqx_version" {
  description = "EMQX version to install"
  type        = string
  default     = "5.3.2"
}

variable "allowed_cidr_ranges" {
  description = "CIDR ranges allowed to access EMQX"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_bucket" {
  description = "GCS bucket name for storing certificates"
  type        = string
  default     = "emqx-certificates-bucket"
}

