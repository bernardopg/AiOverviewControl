# AiOverviewControl

Widget autocontido do DankMaterialShell para cotas, billing, autenticação e telemetria local de provedores de IA.

## Versão 1.3

- O plugin administra todo o pipeline de coleta, sem agregador externo.
- Limites do Codex são lidos pelo protocolo oficial `codex app-server`.
- Copilot reutiliza a sessão autenticada do GitHub para ler o snapshot de cota da conta.
- Os cartões diferenciam cota medida, autenticação, analytics local e cobertura apenas informativa.
- Settings incluem saúde dos pré-requisitos, densidade compacta/confortável e diagnósticos.
- O dashboard inclui filtro quando mais de oito provedores estão configurados.

## Requisitos

- DankMaterialShell sobre Quickshell.
- Comandos principais: `bash`, `jq` e `curl`.
- CLIs ou variáveis de ambiente apenas para os provedores habilitados.

## Instalação

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/AiOverviewControl
cp -a . ~/.config/DankMaterialShell/plugins/AiOverviewControl/
chmod +x ~/.config/DankMaterialShell/plugins/AiOverviewControl/providers/get-*
dms restart
```

Ative o plugin nas configurações do DMS e adicione-o à DankBar.

## Modelo de cobertura

| Cobertura | Significado |
| --- | --- |
| Cota | Uma superfície do provedor ou CLI retorna limite, saldo ou billing. |
| Analytics local | O plugin lê logs ou bancos locais pertencentes ao provedor. |
| Autenticação | Um endpoint documentado valida credenciais, mas não expõe cota pública. |
| Informativo | Não existe API pública somente leitura; o cartão aponta para a tela oficial. |

Consulte [providers.md](./providers.md) e [provider-verification.md](./provider-verification.md).

## Validação

```bash
jq . plugin.json
bash -n providers/get-*
qmllint AiOverviewControlWidget.qml AiOverviewControlSettings.qml AiOverviewControlI18n.qml
./providers/get-codex-usage | jq .
./providers/get-provider-health "codex,claude,copilot" | jq .
./providers/get-provider-usage "codex,claude,copilot" ./providers/get-copilot-usage | jq .
```

O plugin mantém falhas isoladas por provedor e nunca inventa percentuais quando a plataforma não oferece uma API adequada.
