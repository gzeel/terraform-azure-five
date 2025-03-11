variable "location" {
  type    = string
  default = "eu-west"
}

variable "code" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vm_size" {
  type    = string
  default = "Standard_B2ats_v2"
}

variable "username" {
  type    = string
  default = null
}
