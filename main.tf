terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted_key_vaults = true
    }
  }
  skip_provider_registration = true
}

provider "azuread" {}

variable "environment" {
  default = "vulnerable"
}

variable "location" {
  default = "Central India"
}

variable "admin_username" {
  default = "azureuser"
}

variable "pentester_email" {
  description = "Pentester user email (attacker account)"
  default     = "pentester.user@matrix3d.com"
}

# ==================== DATA SOURCES ====================
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Get the existing pentester user
data "azuread_user" "pentester" {
  user_principal_name = var.pentester_email
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

# ==================== RESOURCE GROUP ====================
resource "azurerm_resource_group" "main" {
  name     = "SeasidesTraining"
  location = var.location
  
  tags = {
    Environment = "Vulnerable Lab"
    Purpose     = "Security Training"
  }
}

# ==================== SCENARIO 1: AZURE IAM MISCONFIGURATIONS ====================

# NOTE: Pentester user permissions will be assigned manually after deployment
# Run the setup script in outputs after `terraform apply`

# VULNERABLE: Managed Identity with excessive permissions
resource "azurerm_user_assigned_identity" "vulnerable_identity" {
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  name                = "vulnerable-managed-identity"
}

# NOTE: Role assignments must be done manually due to permission restrictions
# See the manual_setup_commands output after apply

# VULNERABLE: Azure AD Application (Service Principal) with long-lived credentials
resource "azuread_application" "vulnerable_app" {
  display_name = "vulnerable-service-principal"
  owners       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_service_principal" "vulnerable_sp" {
  client_id = azuread_application.vulnerable_app.client_id
  owners    = [data.azurerm_client_config.current.object_id]
}

# VULNERABLE: Create never-expiring credential for service principal
resource "azuread_application_password" "vulnerable_secret" {
  application_id = azuread_application.vulnerable_app.id
  display_name   = "Never-Expiring-Secret"
  end_date       = "2099-12-31T00:00:00Z"
}

# ==================== SCENARIO 2: LOGIC APPS ====================

resource "azurerm_logic_app_workflow" "vulnerable_logic_app" {
  name                = "vulnerable-workflow"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Add system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }
  
  tags = {
    Vulnerability = "Unauthenticated HTTP Trigger"
  }
}

# VULNERABLE: HTTP trigger with NO authentication
resource "azurerm_logic_app_trigger_http_request" "insecure_trigger" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.vulnerable_logic_app.id
  
  schema = jsonencode({
    type = "object"
    properties = {
      secret = {
        type = "string"
      }
      apiKey = {
        type = "string"
      }
    }
  })
}

# VULNERABLE: Logic App action that exposes Key Vault secret
resource "azurerm_logic_app_action_http" "expose_secret_action" {
  name         = "GetSecretFromKeyVault"
  logic_app_id = azurerm_logic_app_workflow.vulnerable_logic_app.id
  method       = "GET"
  
  uri = "https://${azurerm_key_vault.vulnerable_kv.name}.vault.azure.net/secrets/api-key?api-version=7.4"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  depends_on = [azurerm_logic_app_trigger_http_request.insecure_trigger]
}

# ==================== SCENARIO 3: AZURE KEY VAULT ====================

resource "azurerm_key_vault" "vulnerable_kv" {
  name                        = "kv-vuln-${random_string.unique.result}"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  
  # VULNERABLE: Public network access enabled
  public_network_access_enabled = true
  
  # VULNERABLE: Allow all networks
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  # VULNERABLE: Disable soft delete and purge protection
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  tags = {
    Vulnerability = "Public Access + Weak ACLs"
  }
}

# VULNERABLE: Overly permissive access policy for managed identity
resource "azurerm_key_vault_access_policy" "vulnerable_identity_policy" {
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.vulnerable_identity.principal_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Backup", "Restore", "Recover"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge"
  ]
  
  certificate_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Purge"
  ]
}

# Access policy for deploying user (Pratham)
resource "azurerm_key_vault_access_policy" "deployer_policy" {
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge"
  ]
  
  key_permissions = [
    "Get", "List", "Create", "Delete"
  ]
}
resource "azurerm_role_assignment" "pentester_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = data.azuread_user.pentester.object_id
}

resource "azurerm_role_assignment" "pentester_kv_secrets_user" {
  scope                = azurerm_key_vault.vulnerable_kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azuread_user.pentester.object_id
  
  depends_on = [
    azurerm_key_vault.vulnerable_kv,
    azurerm_role_assignment.pentester_reader
  ]
}

resource "azurerm_role_assignment" "pentester_storage_reader" {
  scope                = azurerm_storage_account.vulnerable_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azuread_user.pentester.object_id
  
  depends_on = [
    azurerm_storage_account.vulnerable_storage,
    azurerm_role_assignment.pentester_reader
  ]
}
# VULNERABLE: Access policy for pentester user (to be assigned manually)
# Uncomment after manual role assignments:
# resource "azurerm_key_vault_access_policy" "pentester_policy" {
#   key_vault_id = azurerm_key_vault.vulnerable_kv.id
#   tenant_id    = data.azurerm_client_config.current.tenant_id
#   object_id    = data.azuread_user.pentester.object_id
#   
#   secret_permissions = [
#     "Get", "List"
#   ]
# }

# Access policy for Logic App
resource "azurerm_key_vault_access_policy" "logic_app_policy" {
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_logic_app_workflow.vulnerable_logic_app.identity[0].principal_id
  
  secret_permissions = [
    "Get", "List"
  ]
}

# Store sensitive secrets
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = "P@ssw0rd123!Secret"
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  
  depends_on = [azurerm_key_vault_access_policy.deployer_policy]
}

resource "azurerm_key_vault_secret" "api_key" {
  name         = "api-key"
  value        = "sk_live_abcd1234efgh5678ijkl9012mnop"
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  
  depends_on = [azurerm_key_vault_access_policy.deployer_policy]
}

# VULNERABLE: Store service principal credentials in Key Vault (bad practice)
resource "azurerm_key_vault_secret" "sp_secret" {
  name         = "service-principal-secret"
  value        = azuread_application_password.vulnerable_secret.value
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  
  depends_on = [azurerm_key_vault_access_policy.deployer_policy]
}

resource "azurerm_key_vault_secret" "sp_client_id" {
  name         = "service-principal-client-id"
  value        = azuread_application.vulnerable_app.client_id
  key_vault_id = azurerm_key_vault.vulnerable_kv.id
  
  depends_on = [azurerm_key_vault_access_policy.deployer_policy]
}

# ==================== SCENARIO 4: VIRTUAL MACHINES & NETWORKING ====================

resource "azurerm_virtual_network" "vulnerable_vnet" {
  name                = "vulnerable-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "vulnerable_subnet" {
  name                 = "vulnerable-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vulnerable_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# VULNERABLE: NSG with ports wide open
resource "azurerm_network_security_group" "vulnerable_nsg" {
  name                = "vulnerable-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # VULNERABLE: RDP from anywhere
  security_rule {
    name                       = "AllowRDP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # VULNERABLE: SSH from anywhere
  security_rule {
    name                       = "AllowSSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # VULNERABLE: HTTP from anywhere
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # VULNERABLE: WinRM from anywhere (for remote PowerShell)
  security_rule {
    name                       = "AllowWinRM"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = {
    Vulnerability = "Open Management Ports"
  }
}

resource "azurerm_subnet_network_security_group_association" "vulnerable_assoc" {
  subnet_id                 = azurerm_subnet.vulnerable_subnet.id
  network_security_group_id = azurerm_network_security_group.vulnerable_nsg.id
}

resource "azurerm_public_ip" "vulnerable_pip" {
  name                = "vulnerable-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vulnerable_nic" {
  name                = "vulnerable-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vulnerable_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vulnerable_pip.id
  }
}

# VULNERABLE: Windows VM with weak password and managed identity
resource "azurerm_windows_virtual_machine" "vulnerable_vm" {
  name                = "vulnerable-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B2s_v2"
  admin_username      = var.admin_username
  admin_password      = "WeakPassword123!"  # VULNERABLE
  
  network_interface_ids = [
    azurerm_network_interface.vulnerable_nic.id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  
  # VULNERABLE: Attach managed identity with Contributor permissions
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vulnerable_identity.id]
  }
  
  tags = {
    Vulnerability = "Weak Password + Managed Identity"
  }
}

# VULNERABLE: Enable password authentication (bad practice)
resource "azurerm_virtual_machine_extension" "enable_rdp" {
  name                 = "enable-rdp"
  virtual_machine_id   = azurerm_windows_virtual_machine.vulnerable_vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    commandToExecute = "powershell.exe -Command \"Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -name 'fDenyTSConnections' -Value 0; Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'\""
  })
}

# ==================== SCENARIO 5: STORAGE ACCOUNTS ====================

resource "azurerm_storage_account" "vulnerable_storage" {
  name                     = "stvuln${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # VULNERABLE: Public network access
  public_network_access_enabled = true
  
  # VULNERABLE: Allow shared key access
  shared_access_key_enabled = true
  
  # VULNERABLE: Not enforcing HTTPS
  https_traffic_only_enabled = false
  
  # VULNERABLE: Allow all networks
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # VULNERABLE: Minimum TLS version too low
  min_tls_version = "TLS1_0"
  
  tags = {
    Vulnerability = "Anonymous Access + Weak Security"
  }
}

# VULNERABLE: Container with anonymous blob access
resource "azurerm_storage_container" "vulnerable_container" {
  name                  = "sensitive-data"
  storage_account_name  = azurerm_storage_account.vulnerable_storage.name
  container_access_type = "blob"  # VULNERABLE: Anonymous read access
}

# VULNERABLE: Store sensitive data
resource "azurerm_storage_blob" "sensitive_file" {
  name                   = "confidential.txt"
  storage_account_name   = azurerm_storage_account.vulnerable_storage.name
  storage_container_name = azurerm_storage_container.vulnerable_container.name
  type                   = "Block"
  source_content         = <<-EOT
    === CONFIDENTIAL COMPANY DATA ===
    
    Database Connection:
    Server: prod-db-01.database.windows.net
    Database: CustomerData
    Username: dbadmin
    Password: SecureDb@2024
    
    API Credentials:
    Endpoint: https://api.company.com
    API Key: sk_live_abcd1234efgh5678ijkl9012mnop
    
    Service Principal:
    Client ID: ${azuread_application.vulnerable_app.client_id}
    Tenant ID: ${data.azurerm_client_config.current.tenant_id}
    Secret: (stored in Key Vault: service-principal-secret)
    
    === DO NOT SHARE ===
  EOT
}

# VULNERABLE: Additional sensitive files
resource "azurerm_storage_blob" "customer_data" {
  name                   = "customers.csv"
  storage_account_name   = azurerm_storage_account.vulnerable_storage.name
  storage_container_name = azurerm_storage_container.vulnerable_container.name
  type                   = "Block"
  source_content         = "CustomerID,Name,Email,CreditCard\n1001,John Doe,john@email.com,4532-****-****-1234\n1002,Jane Smith,jane@email.com,5425-****-****-5678"
}

# ==================== OUTPUTS ====================

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "pentester_user_email" {
  value = data.azuread_user.pentester.user_principal_name
  description = "Pentester/Attacker account email"
}

output "pentester_user_object_id" {
  value = data.azuread_user.pentester.object_id
  description = "Pentester user Object ID (needed for manual permissions)"
}

output "vm_public_ip" {
  value = azurerm_public_ip.vulnerable_pip.ip_address
  description = "Public IP of the vulnerable VM"
}

output "vm_admin_username" {
  value = var.admin_username
}

output "vm_admin_password" {
  value     = "WeakPassword123!"
  sensitive = true
}

output "key_vault_name" {
  value = azurerm_key_vault.vulnerable_kv.name
}

output "storage_account_name" {
  value = azurerm_storage_account.vulnerable_storage.name
}

output "storage_account_key" {
  value     = azurerm_storage_account.vulnerable_storage.primary_access_key
  sensitive = true
}

output "logic_app_callback_url" {
  value     = azurerm_logic_app_trigger_http_request.insecure_trigger.callback_url
  sensitive = true
}

output "service_principal_client_id" {
  value = azuread_application.vulnerable_app.client_id
}

output "service_principal_secret" {
  value     = azuread_application_password.vulnerable_secret.value
  sensitive = true
  description = "Service Principal secret (also stored in Key Vault)"
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.vulnerable_identity.client_id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.vulnerable_identity.principal_id
  description = "Managed Identity Principal ID (needed for manual role assignment)"
}

output "service_principal_object_id" {
  value = azuread_service_principal.vulnerable_sp.object_id
  description = "Service Principal Object ID (needed for manual role assignment)"
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}

# ==================== MANUAL SETUP COMMANDS ====================

output "manual_setup_script" {
  value = <<-EOT
# ========================================
# MANUAL SETUP SCRIPT - RUN AS PRATHAM
# ========================================
# Save this as setup-permissions.ps1 and run it

Write-Host "=== Manual Permission Setup ===" -ForegroundColor Cyan

# Get all resource IDs from Terraform
$PENTESTER_OID = (terraform output -raw pentester_user_object_id)
$MI_PRINCIPAL = (terraform output -raw managed_identity_principal_id)
$SP_OBJECT_ID = (terraform output -raw service_principal_object_id)
$SP_CLIENT_ID = (terraform output -raw service_principal_client_id)
$KV_NAME = (terraform output -raw key_vault_name)
$STORAGE_NAME = (terraform output -raw storage_account_name)

Write-Host "Pentester Object ID: $PENTESTER_OID" -ForegroundColor Yellow
Write-Host "Managed Identity Principal: $MI_PRINCIPAL" -ForegroundColor Yellow
Write-Host "Service Principal Object ID: $SP_OBJECT_ID" -ForegroundColor Yellow
Write-Host "Service Principal Client ID: $SP_CLIENT_ID" -ForegroundColor Yellow
Write-Host ""

# 1. Assign Reader to Pentester
Write-Host "[1/5] Assigning Reader to Pentester..." -ForegroundColor Cyan
az role assignment create `
  --assignee $PENTESTER_OID `
  --role "Reader" `
  --resource-group SeasidesTraining

# 2. Assign Key Vault access to Pentester
Write-Host "[2/5] Assigning Key Vault access to Pentester..." -ForegroundColor Cyan
az keyvault set-policy `
  --name $KV_NAME `
  --object-id $PENTESTER_OID `
  --secret-permissions get list

# 3. Assign Storage access to Pentester
Write-Host "[3/5] Assigning Storage Blob Data Reader to Pentester..." -ForegroundColor Cyan
az role assignment create `
  --assignee $PENTESTER_OID `
  --role "Storage Blob Data Reader" `
  --scope "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/SeasidesTraining/providers/Microsoft.Storage/storageAccounts/$STORAGE_NAME"

# 4. Assign Contributor to Managed Identity (VULNERABLE!)
Write-Host "[4/5] Assigning Contributor to Managed Identity (VULNERABLE)..." -ForegroundColor Red
az role assignment create `
  --assignee $MI_PRINCIPAL `
  --role "Contributor" `
  --resource-group SeasidesTraining

# 5. Assign Contributor to Service Principal (VULNERABLE!)
Write-Host "[5/5] Assigning Contributor to Service Principal (VULNERABLE)..." -ForegroundColor Red
az role assignment create `
  --assignee $SP_CLIENT_ID `
  --role "Contributor" `
  --scope "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/SeasidesTraining"

Write-Host ""
Write-Host "✅ All permissions assigned successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "=== Verification Commands ===" -ForegroundColor Cyan
Write-Host "Test Pentester access:" -ForegroundColor Yellow
Write-Host "  az login -u pentester.user@matrix3d.com" -ForegroundColor White
Write-Host "  az keyvault secret list --vault-name $KV_NAME" -ForegroundColor White
Write-Host ""
Write-Host "Test Service Principal access:" -ForegroundColor Yellow
Write-Host "  az logout" -ForegroundColor White
Write-Host "  az login --service-principal -u $SP_CLIENT_ID -p [GET_FROM_KEYVAULT] --tenant ${data.azurerm_client_config.current.tenant_id}" -ForegroundColor White
Write-Host "  az resource list --resource-group SeasidesTraining" -ForegroundColor White

# ========================================
  EOT
  description = "Complete PowerShell script to assign all permissions"
}

output "pentester_attack_info" {
  sensitive = true
  value = <<-EOT
    
    ========================================
    PENTESTER ATTACK STARTING POINT
    ========================================
    
    Pentester Account: ${data.azuread_user.pentester.user_principal_name}
    
    Initial Permissions (after manual setup):
    - Reader (Resource Group)
    - Key Vault Secrets User (Get, List)
    - Storage Blob Data Reader
    
    Attack Surface:
    1. VM RDP: ${azurerm_public_ip.vulnerable_pip.ip_address}:3389
       Username: ${var.admin_username}
       Password: WeakPassword123!
    
    2. Storage (Anonymous Access): 
       https://${azurerm_storage_account.vulnerable_storage.name}.blob.core.windows.net/sensitive-data/
    
    3. Key Vault:
       https://${azurerm_key_vault.vulnerable_kv.name}.vault.azure.net/
    
    4. Service Principal (in Key Vault):
       Client ID: ${azuread_application.vulnerable_app.client_id}
       Tenant ID: ${data.azurerm_client_config.current.tenant_id}
    
    Login as Pentester:
    az login -u ${data.azuread_user.pentester.user_principal_name}
    
    Start with:
    az resource list --resource-group SeasidesTraining --output table
    az keyvault secret list --vault-name ${azurerm_key_vault.vulnerable_kv.name}
    
    ========================================
  EOT
}