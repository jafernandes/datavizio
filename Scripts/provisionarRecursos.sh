#!/bin/bash

# Função para abortar em caso de falha e limpar recursos
abort_on_failure() {
  echo "Erro ao criar $1. Limpando recursos..."
  clean_up_resources
  exit 1
}

# Função para limpar recursos
clean_up_resources() {
  echo "Limpando recursos criados..."
  az group delete --name $resourceGroupName --yes --no-wait
  az group delete --name $managedResourceGroupName --yes --no-wait
  echo "Recursos removidos. Saindo..."
}

# Seleção da assinatura
echo "Listando assinaturas disponíveis..."
az account list --output table
read -p "Digite o ID da assinatura que deseja utilizar: " subscriptionId
az account set --subscription $subscriptionId

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração interativo do Azure!"
read -p "Digite o nome do cliente: " clientName
read -p "Digite o local (ex: eastus): " location
read -p "Quantos Key Vaults deseja criar? " kvCount

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"
managedResourceGroupName="synapseworkspace-managedrg-${clientName}"
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

# Criar Grupo de Recursos
echo "Criando o grupo de recursos..."
az group create --name $resourceGroupName --location $location || abort_on_failure "grupo de recursos"

# Criar Conta de Armazenamento com Azure Data Lake Storage Gen 2
echo "Criando a conta de armazenamento..."
az storage account create --name $storageAccountName --resource-group $resourceGroupName --location $location --sku Standard_LRS --kind StorageV2 --hns true || abort_on_failure "conta de armazenamento"

# Criar Containers na Conta de Armazenamento com autenticação Microsoft Entra
echo "Criando containers na conta de armazenamento..."
az storage container create --name bronze --account-name $storageAccountName --auth-mode login || abort_on_failure "container bronze"
az storage container create --name silver --account-name $storageAccountName --auth-mode login || abort_on_failure "container silver"
az storage container create --name gold --account-name $storageAccountName --auth-mode login || abort_on_failure "container gold"

# Criar Azure Data Factory
echo "Criando o Azure Data Factory..."
az datafactory create --resource-group $resourceGroupName --name $dataFactoryName --location $location || abort_on_failure "Azure Data Factory"

# Criar Synapse Workspace com pool SQL built-in
echo "Criando o Synapse Workspace..."
az synapse workspace create --name $synapseWorkspaceName --resource-group $resourceGroupName --location $location --storage-account $storageAccountName --file-system default --sql-admin-login-user $sqlAdminLogin --sql-admin-login-password $sqlAdminPassword --repository-type None || abort_on_failure "Synapse Workspace"

# Obter o nome do grupo de recursos gerenciado e renomeá-lo
managedResourceGroup=$(az group list --query "[?contains(name, 'synapseworkspace-managedrg')].{name:name}" --output tsv)
if [[ -n $managedResourceGroup ]]; then
  echo "Renomeando grupo de recursos gerenciado..."
  az group update --name $managedResourceGroup --set name=$managedResourceGroupName || abort_on_failure "renomeação do grupo de recursos gerenciado"
fi

# Criar e configurar Key Vaults
for kvName in "${keyVaultNames[@]}"
do
  echo "Criando o Azure Key Vault $kvName..."
  az keyvault create --name $kvName --resource-group $resourceGroupName --location $location || abort_on_failure "Key Vault $kvName"
  echo "Configurando Key Vault $kvName..."
  secrets="keyVaultSecrets_$kvName[@]"
  for secretName in "${!secrets}"
  do
    secretValue=${secrets[$secretName]}
    az keyvault secret set --vault-name $kvName --name $secretName --value $secretValue || abort_on_failure "segredo $secretName no Key Vault $kvName"
  done
done

# Tags
echo "Adicionando tags aos recursos..."
resources=$(az resource list --resource-group $resourceGroupName --query "[].id" --output tsv)
for resource in $resources; do
  az resource tag --tags ClientName=$clientName --ids $resource --resource-type Microsoft.Resources/subscriptions/resourceGroups || abort_on_failure "tag nos recursos"
done

echo "Criação de recursos concluída."
