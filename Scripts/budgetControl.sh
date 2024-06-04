#!/bin/bash

# Função para abortar em caso de falha
abort_on_failure() {
  echo "Erro ao configurar notificações e budget para $1. Saindo..."
  exit 1
}

# Definir a assinatura e a localização padrão
subscriptionId="0448ce1f-bab4-4d30-bed8-ce1615fd1b5e"
location="eastus"
az account set --subscription $subscriptionId

# Solicitar informações ao usuário
echo "Bem-vindo ao processo de configuração de notificações e budget do Azure!"
read -p "Digite o nome do cliente: " clientName

# Nomear os recursos de acordo com as convenções
resourceGroupName="rg-${clientName}"

# Configurar Budget
echo "Configurando o Budget..."

# Criar o orçamento mensal
az consumption budget create --budget-name "monthly-budget" --resource-group $resourceGroupName --amount 20 --time-grain Monthly --start-date $(date +%Y-%m-01) --end-date $(date -d "+1 year" +%Y-%m-01) --category Cost || abort_on_failure "Budget Mensal"

# Criar o orçamento diário
az consumption budget create --budget-name "daily-budget" --resource-group $resourceGroupName --amount 10 --time-grain Daily --start-date $(date +%Y-%m-01) --end-date $(date -d "+1 year" +%Y-%m-01) --category Cost || abort_on_failure "Budget Diário"

echo "Configuração de Budget concluída."

# Configurar ação de grupo de ação para notificações por e-mail
echo "Configurando notificações por e-mail..."

az monitor action-group create --name "${clientName}-budget-action-group" --resource-group $resourceGroupName --short-name "${clientName}-budget-action" --email Joelfernandes@datavizio.com.br --enabled true || abort_on_failure "Ação de Grupo de Ação para Notificações por E-mail"

echo "Ação de Grupo de Ação para Notificações por E-mail configurada."

# Vincular a ação ao alerta de gastos mensais
echo "Configurando alerta para orçamento mensal..."

az monitor alert create --name "${clientName}-monthly-budget-alert" --resource-group $resourceGroupName --condition "spending > 90" --description "Notificação de orçamento mensal para o cliente ${clientName}" --target "subscription/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Consumption/budgets/monthly-budget" --action "${clientName}-budget-action" --frequency "Hour" --time-grain "1" --timezone "UTC" --start-date "$(date -u '+%Y-%m-%dT11:00:00')" --end-date "$(date -u '+%Y-%m-%dT18:00:00')" || abort_on_failure "Alerta para Orçamento Mensal"

# Vincular a ação ao alerta de gastos diários
echo "Configurando alerta para orçamento diário..."

az monitor alert create --name "${clientName}-daily-budget-alert" --resource-group $resourceGroupName --condition "spending > 90" --description "Notificação de orçamento diário para o cliente ${clientName}" --target "subscription/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Consumption/budgets/daily-budget" --action "${clientName}-budget-action" --frequency "Hour" --time-grain "1" --timezone "UTC" --start-date "$(date -u '+%Y-%m-%dT11:00:00')" --end-date "$(date -u '+%Y-%m-%dT18:00:00')" || abort_on_failure "Alerta para Orçamento Diário"

echo "Configuração de notificações por e-mail concluída."
