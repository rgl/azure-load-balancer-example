# NB you can test the relative speed from you browser to a location using https://azurespeedtest.azurewebsites.net/
# get the available locations with: az account list-locations --output table
variable "location" {
  default = "France Central" # see https://azure.microsoft.com/en-us/global-infrastructure/france/
}

# NB this name must be unique within the Azure subscription.
#    all the other names must be unique within this resource group.
variable "resource_group_name" {
  default = "rgl-load-balancer-example"
}

variable "admin_username" {
  default = "rgl"
}

variable "admin_password" {
  default = "HeyH0Password"
}

variable "web_vm_count" {
  default = "2"
}

# NB when you run make terraform-apply this is set from the TF_VAR_admin_ssh_key_data environment variable, which comes from the ~/.ssh/id_rsa.pub file.
variable "admin_ssh_key_data" {}

output "app1_load_balancer_ip_address" {
  value = "${azurerm_public_ip.app1.ip_address}"
}

output "app2_load_balancer_ip_address" {
  value = "${azurerm_public_ip.app2.ip_address}"
}

provider "azurerm" {}

resource "azurerm_resource_group" "example" {
  name     = "${var.resource_group_name}" # NB this name must be unique within the Azure subscription.
  location = "${var.location}"
}

# NB this generates a single random number for the resource group.
resource "random_id" "example" {
  keepers = {
    resource_group = "${azurerm_resource_group.example.name}"
  }

  byte_length = 8
}

resource "azurerm_storage_account" "diagnostics" {
  # NB this name must be globally unique as all the azure storage accounts share the same namespace.
  # NB this name must be at most 24 characters long.
  name = "diag${random_id.example.hex}"

  resource_group_name      = "${azurerm_resource_group.example.name}"
  location                 = "${azurerm_resource_group.example.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_network" "example" {
  name                = "example"
  address_space       = ["10.102.0.0/16"]
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = "${azurerm_resource_group.example.name}"
  virtual_network_name = "${azurerm_virtual_network.example.name}"
  address_prefix       = "10.102.2.0/24"
}

resource "azurerm_public_ip" "app1" {
  name                         = "app1"
  resource_group_name          = "${azurerm_resource_group.example.name}"
  location                     = "${azurerm_resource_group.example.location}"
  public_ip_address_allocation = "Static"
}

resource "azurerm_public_ip" "app2" {
  name                         = "app2"
  resource_group_name          = "${azurerm_resource_group.example.name}"
  location                     = "${azurerm_resource_group.example.location}"
  public_ip_address_allocation = "Static"
}

resource "azurerm_lb" "web" {
  name                = "web"
  resource_group_name = "${azurerm_resource_group.example.name}"
  location            = "${azurerm_resource_group.example.location}"
  sku                 = "Basic"

  frontend_ip_configuration {
    name                 = "app1"
    public_ip_address_id = "${azurerm_public_ip.app1.id}"
  }

  frontend_ip_configuration {
    name                 = "app2"
    public_ip_address_id = "${azurerm_public_ip.app2.id}"
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  resource_group_name = "${azurerm_resource_group.example.name}"
  loadbalancer_id     = "${azurerm_lb.web.id}"
  name                = "web"
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
  count                   = "${var.web_vm_count}"
  network_interface_id    = "${azurerm_network_interface.web.*.id[count.index]}"
  ip_configuration_name   = "web"
  backend_address_pool_id = "${azurerm_lb_backend_address_pool.web.id}"
}

resource "azurerm_lb_probe" "app1" {
  resource_group_name = "${azurerm_resource_group.example.name}"
  loadbalancer_id     = "${azurerm_lb.web.id}"
  name                = "app1-healthz"
  protocol            = "Http"
  port                = 3101
  request_path        = "/healthz"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_probe" "app2" {
  resource_group_name = "${azurerm_resource_group.example.name}"
  loadbalancer_id     = "${azurerm_lb.web.id}"
  name                = "app2-healthz"
  protocol            = "Http"
  port                = 3201
  request_path        = "/healthz"
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "app1" {
  resource_group_name            = "${azurerm_resource_group.example.name}"
  name                           = "app1"
  loadbalancer_id                = "${azurerm_lb.web.id}"
  probe_id                       = "${azurerm_lb_probe.app1.id}"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.web.id}"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 3100
  frontend_ip_configuration_name = "app1"
  idle_timeout_in_minutes        = 4
  load_distribution              = "Default"
}

resource "azurerm_lb_rule" "app2" {
  resource_group_name            = "${azurerm_resource_group.example.name}"
  name                           = "app2"
  loadbalancer_id                = "${azurerm_lb.web.id}"
  probe_id                       = "${azurerm_lb_probe.app2.id}"
  backend_address_pool_id        = "${azurerm_lb_backend_address_pool.web.id}"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 3200
  frontend_ip_configuration_name = "app2"
  idle_timeout_in_minutes        = 4
  load_distribution              = "Default"
}

resource "azurerm_availability_set" "web" {
  name                         = "web"
  resource_group_name          = "${azurerm_resource_group.example.name}"
  location                     = "${azurerm_resource_group.example.location}"
  managed                      = true
  platform_fault_domain_count  = 2
  platform_update_domain_count = 5
}

resource "azurerm_network_security_group" "web" {
  name                = "web"
  resource_group_name = "${azurerm_resource_group.example.name}"
  location            = "${azurerm_resource_group.example.location}"

  # NB By default, a security group, will have the following Inbound rules:
  #     | Priority | Name                           | Port  | Protocol  | Source            | Destination     | Action  |
  #     |----------|--------------------------------|-------|-----------|-------------------|-----------------|---------|
  #     | 65000    | AllowVnetInBound               | Any   | Any       | VirtualNetwork    | VirtualNetwork  | Allow   |
  #     | 65001    | AllowAzureLoadBalancerInBound  | Any   | Any       | AzureLoadBalancer | Any             | Allow   |
  #     | 65500    | DenyAllInBound                 | Any   | Any       | Any               | Any             | Deny    |
  # NB By default, a security group, will have the following Outbound rules:
  #     | Priority | Name                           | Port  | Protocol  | Source            | Destination     | Action  |
  #     |----------|--------------------------------|-------|-----------|-------------------|-----------------|---------|
  #     | 65000    | AllowVnetOutBound              | Any   | Any       | VirtualNetwork    | VirtualNetwork  | Allow   |
  #     | 65001    | AllowInternetOutBound          | Any   | Any       | Any               | Internet        | Allow   |
  #     | 65500    | DenyAllOutBound                | Any   | Any       | Any               | Any             | Deny    |

  security_rule {
    name                       = "app1"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3100"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "app2"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3200"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "web" {
  count                     = "${var.web_vm_count}"
  name                      = "web${count.index + 1}"
  resource_group_name       = "${azurerm_resource_group.example.name}"
  location                  = "${azurerm_resource_group.example.location}"
  network_security_group_id = "${azurerm_network_security_group.web.id}"

  ip_configuration {
    name                          = "web"
    primary                       = true
    subnet_id                     = "${azurerm_subnet.backend.id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.102.2.${count.index + 4}"  # NB Azure reserves the first four addresses in each subnet address range, so do not use those.
  }
}

resource "azurerm_virtual_machine" "web" {
  count                 = "${var.web_vm_count}"
  name                  = "web${count.index + 1}"
  resource_group_name   = "${azurerm_resource_group.example.name}"
  location              = "${azurerm_resource_group.example.location}"
  network_interface_ids = ["${azurerm_network_interface.web.*.id[count.index]}"]
  availability_set_id   = "${azurerm_availability_set.web.id}"
  vm_size               = "Standard_B1s"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_os_disk {
    name          = "web${count.index + 1}_os"
    caching       = "ReadWrite"                # TODO is this advisable?
    create_option = "FromImage"

    #disk_size_gb      = "30"              # this is optional.
    managed_disk_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

  # see https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cli-ps-findimage
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_profile {
    computer_name  = "web${count.index + 1}"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
    custom_data    = "${base64gzip(file("provision-web.sh"))}"
  }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${var.admin_ssh_key_data}"
    }
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.diagnostics.primary_blob_endpoint}"
  }
}
