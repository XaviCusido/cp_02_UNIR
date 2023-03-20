# Creación del grupo de recursos
resource "azurerm_resource_group" "rg" {
	name		= var.resource_group_name
	location	= var.location_name
}
# Creación de la virtual network
resource "azurerm_virtual_network" "vnet" {
	name			= var.network_name
	address_space		= ["10.0.0.0/16"]
	location		= azurerm_resource_group.rg.location
	resource_group_name	= azurerm_resource_group.rg.name
}
#Creación de la subred.
resource "azurerm_subnet" "subnet" {
	name			= var.subnet_name
	resource_group_name	= azurerm_resource_group.rg.name
	virtual_network_name	= azurerm_virtual_network.vnet.name
	address_prefixes	= ["10.0.2.0/24"]
}
#Ip pública para la VM
resource "azurerm_public_ip" "pip" {
	name			= "VIP"
	location		= azurerm_resource_group.rg.location
	resource_group_name	= azurerm_resource_group.rg.name
	allocation_method	= "Static"
	sku			= "Standard"
}
# Creación de la nic para la VM asociación de la virtual IP.
resource "azurerm_network_interface" "nic" {

  name                = "vnic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {

    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id	  = azurerm_public_ip.pip.id
  }

}
# Creación de la VM Linux, con un usuario y vinculación de la nic.
resource "azurerm_linux_virtual_machine" "vm" {

  name                = "vm1"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_F2"
  admin_username      = "azureuser"
  network_interface_ids = [
  	azurerm_network_interface.nic.id,
  ]

# Creación credenciales de acceso SSH. 
admin_ssh_key {

    username   = "azureuser"
    public_key = file("/ssh/keys-ej-1/azure.pub")

  }

os_disk {

    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"

  }

  plan {

    name      = "centos-8-stream-free"
    product   = "centos-8-stream-free"
    publisher = "cognosys"
  }

  source_image_reference {

    publisher = "cognosys"
    offer     = "centos-8-stream-free"
    sku       = "centos-8-stream-free"
    version   = "22.03.28"

  }
}
# Creación del grupo de seguridad con dos reglas para el pueto 22 y 80.
resource "azurerm_network_security_group" "nsg1" {
  name                = "securitygroup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
 security_rule {
    name                       = "http"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}
# Asociación del network security group con la subnet.
resource "azurerm_subnet_network_security_group_association" "nsg-link" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg1.id
}

# Creación del container registry.
resource "azurerm_container_registry" "acr" {
  name                = "acrxavicusido"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = false
}
# Creación del AKS.
resource "azurerm_kubernetes_cluster" "k8s" {
  name                = "example-aks1"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "exampleaks1"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}

resource "azurerm_role_assignment" "enablePulling" {
  principal_id                     = azurerm_kubernetes_cluster.k8s.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
