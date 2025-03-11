terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.15.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  resource_provider_registrations = "none"
  subscription_id = "c064671c-8f74-4fec-b088-b53c568245eb"
  features {}
}

provider "random" {}

# Generate unique code
resource "random_string" "code" {
  length  = 5
  special = false
  upper   = false
}

locals {
  code = coalesce(var.code, random_string.code.result)
  username = var.username
  tags = merge(var.tags, {
    DeployedOn = timestamp()
  })
  # Define the number of VM instances to create
  instance_count = 5
  # Generate a list of instance indices
  instance_indices = range(local.instance_count)
}

# Use existing Resource Group
data "azurerm_resource_group" "rg" {
  name = "fe2157786"
}

# Get existing SSH Key
data "azurerm_ssh_public_key" "ssh_key" {
  name                = "azure_macbookpro"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# NSG - Shared resource
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-wg-${local.code}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = local.tags

  # Modified rule to allow SSH from anywhere
  security_rule {
    name                       = "Allow-SSH-Inbound"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"  # Modified to allow from any source
    destination_address_prefix = "VirtualNetwork"
  }
}

# VNet - Shared resource
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-wg-${local.code}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.13.13.0/24"]
  tags                = local.tags

  subnet {
    name             = "snet-wg-${local.code}"
    address_prefixes = ["10.13.13.0/25"]
    security_group   = azurerm_network_security_group.nsg.id
  }
}

# Public IPs - One per instance
resource "azurerm_public_ip" "pip" {
  count               = local.instance_count
  name                = "pip-wg-${local.code}-${count.index}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"
  domain_name_label   = "pip-wg-${local.code}-${count.index}"
  tags                = local.tags
}

# NICs - One per instance
resource "azurerm_network_interface" "nic" {
  count                         = local.instance_count
  name                          = "nic-wg-${local.code}-${count.index}"
  location                      = data.azurerm_resource_group.rg.location
  resource_group_name           = data.azurerm_resource_group.rg.name
  tags                          = local.tags

  accelerated_networking_enabled = true
  ip_forwarding_enabled          = true

  ip_configuration {
    name                          = "ipconfig-wg-${local.code}-${count.index}"
    subnet_id                     = azurerm_virtual_network.vnet.subnet.*.id[0]
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[count.index].id
  }
}

# VMs - One per instance
resource "azurerm_linux_virtual_machine" "vm" {
  count               = local.instance_count
  name                = "vm-wg-${local.code}-${count.index}"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = local.username
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.nic[count.index].id]

  admin_ssh_key {
    username   = local.username
    public_key = data.azurerm_ssh_public_key.ssh_key.public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-wg-${local.code}-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  identity {
    type = "SystemAssigned"
  }

  vtpm_enabled        = true
  secure_boot_enabled = true
}
