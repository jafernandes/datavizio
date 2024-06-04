#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro: $1. Abortando operação."
  exit 1
}

# Solicitar informações ao usuário
read -p "Digite o nome do cliente: " clientName
read -p "Digite o local (ex: eastus): " location
read -p "Digite a assinatura a ser usada: " subscriptionId
read -p "Quantos Key Vaults deseja criar? " kvCount

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"
storageAccountName="st${clientName}$(date +%s)"
dataFactoryName="adf-${clientName}"
synapseWorkspaceName="synapse-${clientName}"
keyVaultNames=()
sqlAdminLogin="sqladmin-${clientName}"
read -s -p "Digite a senha do administrador SQL: " sqlAdminPassword
echo

# Solicitar informações para os Key Vaults
for (( i=1; i<=$kvCount; i++ ))
do
  read -p "Digite o nome do Key Vault #$i: " kvName
  keyVaultNames+=($kvName)
  declare "keyVaultSecrets_$kvName=()"
  read -p "Quantos segredos deseja adicionar no Key Vault $kvName? " secretCount
  for (( j=1; j<=$secretCount; j++ ))
  do
    read -p "Digite o nome do segredo #$j para $kvName: " secretName
    read -s -p "Digite o valor do segredo $secretName: " secretValue
    echo
    declare "keyVaultSecrets_$kvName+=([$secretName]=$secretValue)"
  done
done

# Mostrar ao usuário como os recursos serão nomeados
echo "Os recursos serão nomeados da seguinte forma:"
echo "Grupo de Recursos: $resourceGroupName"
echo "Conta de Armazenamento: $storageAccountName"
echo "Data Factory: $dataFactoryName"
echo "Synapse Workspace: $synapseWorkspaceName"
echo "Key Vaults: ${keyVaultNames[@]}"
echo "Usuário SQL: $sqlAdminLogin"

# Confirmar com o usuário
read -p "Deseja continuar com esses nomes? (s/n): " confirm
if [[ $confirm != "s" ]]; then
  echo "Processo cancelado."
  exit 1
fi

# Configurar a assinatura
az account set --subscription $subscriptionId || abort_on_failure "configurar a assinatura"

# Criar Grupo de Recursos
echo "Criando o grupo de recursos..."
az group create --name $resourceGroupName --location $location --tags Client=$clientName || abort_on_failure "grupo de recursos"

# Criar Conta de Armazenamento
echo "Criando a conta de armazenamento..."
storageSku="Standard_LRS"

az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location --sku $storageSku --kind StorageV2 --hns true || abort_on_failure "conta de armazenamento"

# Criar Containers na Conta de Armazenamento
echo "Criando containers na conta de armazenamento..."
az storage container create --name bronze --account-name $storageAccountName --auth-mode login || abort_on_failure "container bronze"
az storage container create --name silver --account-name $storageAccountName --auth-mode login || abort_on_failure "container silver"
az storage container create --name gold --account-name $storageAccountName --auth-mode login || abort_on_failure "container gold"

# Criar Azure Data Factory
echo "Criando o Azure Data Factory..."
az datafactory create --resource-group $resourceGroupName --name $dataFactoryName --location $location --tags Client=$clientName || abort_on_failure "Azure Data Factory"

# Criar Synapse Workspace sem configuração de SKU
echo "Criando o Synapse Workspace..."
az synapse workspace create --name $synapseWorkspaceName --resource-group $resourceGroupName --location $location --storage-account $storageAccountName --file-system default --sql-admin-login-user $sqlAdminLogin --sql-admin-login-password $sqlAdminPassword --tags Client=$clientName || abort_on_failure "Synapse Workspace"

# Criar e configurar Key Vaults
for kvName in "${keyVaultNames[@]}"
do
  echo "Criando o Azure Key Vault $kvName..."
  az keyvault create --name $kvName --resource-group $resourceGroupName --location $location --tags Client=$clientName || abort_on_failure "Key Vault $kvName"
  echo "Configurando Key Vault $kvName..."
  secrets="keyVaultSecrets_$kvName[@]"
  for secretName in "${!secrets}"
  do
    secretValue=${secrets[$secretName]}
    az keyvault secret set --vault-name $kvName --name $secretName --value $secretValue || abort_on_failure "segredo $secretName no Key Vault $kvName"
  done
done
