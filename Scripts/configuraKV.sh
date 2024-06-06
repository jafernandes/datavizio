#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro ao configurar o Key Vault $1. Saindo..."
  exit 1
}

# Função para verificar se um Key Vault existe
keyvault_exists() {
  az keyvault show --name $1 &>/dev/null
}

# Solicitar a assinatura
echo "Obtendo a lista de assinaturas disponíveis..."
az account list --output table

read -p "Digite o ID da assinatura que você deseja usar: " subscriptionId
az account set --subscription $subscriptionId

# Solicitar a localização
read -p "Digite a localização (exemplo: eastus): " location

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração de Key Vaults no Azure!"
read -p "Digite o nome do cliente: " clientName

# Nomear os recursos de acordo com as convenções
keyVaultName="kv${clientName}"
resourceGroupName="rg-${clientName}"

# Verifica se o Key Vault existe; caso contrário, cria um
if keyvault_exists $keyVaultName; then
  echo "O Key Vault $keyVaultName já existe."
else
  echo "Criando Key Vault $keyVaultName..."
  az keyvault create --name $keyVaultName --resource-group $resourceGroupName --location $location || abort_on_failure $keyVaultName
  echo "Key Vault $keyVaultName criado com sucesso."
fi

# Alterar o modelo de permissão para Vault Access Policy
echo "Alterando o modelo de permissão para Vault Access Policy..."
az keyvault update --name $keyVaultName --resource-group $resourceGroupName --set properties.enableRbacAuthorization=false || abort_on_failure $keyVaultName
echo "Modelo de permissão alterado com sucesso."

# Adicionar permissões ao usuário
user_id=$(az ad signed-in-user show --query id -o tsv)
az keyvault set-policy --name $keyVaultName --object-id $user_id --secret-permissions get list set delete --key-permissions get list create delete --certificate-permissions get list create delete || abort_on_failure $keyVaultName
echo "Permissões ajustadas para o usuário atual no Key Vault $keyVaultName."

# Solicitar o número de segredos
read -p "Quantos segredos você quer adicionar ao Key Vault $keyVaultName? " secret_count

# Loop para adicionar cada segredo
for ((j=1; j<=$secret_count; j++))
do
  read -p "Digite o nome do segredo $j: " secret_name
  read -p "Digite o valor do segredo $j: " secret_value
  az keyvault secret set --vault-name $keyVaultName --name $secret_name --value $secret_value || abort_on_failure $keyVaultName
  echo "Segredo $secret_name adicionado ao Key Vault $keyVaultName."
done

# Autorizar Azure Data Factory a acessar os segredos
adf_name="adf-${clientName}"
adf_id=$(az datafactory show --name $adf_name --resource-group $resourceGroupName --query identity.principalId -o tsv)

if [[ -z "$adf_id" ]]; then
  echo "Erro: Não foi possível encontrar o Azure Data Factory $adf_name. Verifique se o nome está correto."
  exit 1
fi

az keyvault set-policy --name $keyVaultName --object-id $adf_id --secret-permissions get list || abort_on_failure $keyVaultName
echo "Azure Data Factory $adf_name autorizado a acessar os segredos no Key Vault $keyVaultName."

echo "Configuração de Key Vaults concluída."
