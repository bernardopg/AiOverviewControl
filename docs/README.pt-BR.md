<div align="center">

<img src="./assets/logo.png" alt="Mascote do AiOverviewControl" width="140" />

# AiOverviewControl

**Todas as cotas de IA que você paga, ao vivo na sua DankBar.**

Um plugin para o [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) que acompanha
cota, cobrança, autenticação e uso local de 37 provedores de IA — localmente, com honestidade
e sem nenhum serviço externo.

[![Release](https://img.shields.io/github/v/release/bernardopg/AiOverviewControl?color=8B5CF6&label=release)](https://github.com/bernardopg/AiOverviewControl/releases/latest)
[![CI](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml/badge.svg)](https://github.com/bernardopg/AiOverviewControl/actions/workflows/ci.yml)
[![Provedores](https://img.shields.io/badge/provedores-37-8B5CF6)](./providers.md)
[![Idiomas](https://img.shields.io/badge/idiomas-5-00BFA5)](./i18n-crowdin.md)
[![Licença](https://img.shields.io/github/license/bernardopg/AiOverviewControl?color=64748B)](../LICENSE)

[**Demonstração**](#-demonstração) · [**Instalar**](#-início-rápido) · [**Capturas**](#-de-perto) · [**Provedores**](./providers.md) · [**Documentação**](#-documentação) · [**Apoie**](#-apoie-o-projeto) · [English](../README.md)

<br />

<img src="./assets/banner.jpg" alt="AiOverviewControl" width="100%" />

</div>

## 🎬 Demonstração

<div align="center">

<img src="./assets/demo.gif" alt="Demonstração do AiOverviewControl" width="100%" />

<sub><a href="./assets/demo.mp4">MP4 em alta qualidade</a></sub>

</div>

## ✨ Por que AiOverviewControl

Você paga Claude, Codex, Copilot, OpenRouter… e cada um esconde a cota num
painel, CLI ou API diferente. O AiOverviewControl lê cada provedor
**de forma independente e na sua máquina**, e mostra uma visão única.

Ele mostra dados medidos quando existe uma fonte real, e diz claramente quando
um provedor só confirma autenticação ou é apenas informativo. Nada de raspar
painéis. Nada de porcentagens inventadas.

## 🚀 Recursos

<table>
<tr>
<td width="50%" valign="top">

**📊 Um painel, 37 provedores**<br />
Cota, saldo, analytics e autenticação lado a lado, com visão geral da frota:
carga média, provedor mais usado e próximo reset.

</td>
<td width="50%" valign="top">

**🎯 Uma pílula que diz a verdade**<br />
Escolha qual janela de cota cada provedor mostra na barra, ou siga a mais
apertada. Passe o mouse para ver a janela e o reset. Barra lotada? Esconda
os nomes e compacte o espaçamento.

</td>
</tr>
<tr>
<td valign="top">

**🤖 Telemetria local detalhada**<br />
Claude, 9Router, pi e Hermes mostram tokens, custo, modelos e projetos com
gráfico de sete dias — lidos de dados que já estão no seu disco.

</td>
<td valign="top">

**🔔 Alertas de cota**<br />
Notificações em 75, 85 ou 95% — ou limites por provedor — atualizadas no
lugar, sem enxurrada. Clique numa para abrir o card do provedor.

</td>
</tr>
<tr>
<td valign="top">

**🛡️ Privado e resiliente**<br />
Segredos nunca aparecem. Um provedor com falha nunca esconde os saudáveis.
Nenhum endpoint pago é chamado só para testar uma chave.

</td>
<td valign="top">

**🌍 Cinco idiomas**<br />
English, Português (Brasil), Español, Deutsch e 简体中文 — incluindo todos os
rótulos que os adaptadores dos provedores enviam.

</td>
</tr>
</table>

## 📸 De perto

<table>
<tr>
<td align="center" width="50%"><img src="./assets/settings.png" alt="Janela de configurações" /><br /><sub><b>Janela de configurações</b> — também em Configurações do DMS → Plugins</sub></td>
<td align="center" width="50%"><img src="./assets/about.png" alt="Janela Sobre" /><br /><sub><b>Sobre</b> — versão, desenvolvedor e formas de apoiar o projeto</sub></td>
</tr>
</table>

## ⚡ Início rápido

**1. Instale** pela loja de plugins do DMS:

```bash
dms plugins install aiOverviewControl
```

Ou procure **AiOverviewControl** em Configurações do DMS → Plugins, ou no
[diretório Dank Plugins](https://danklinux.com/plugins).

**2. Adicione o widget** a uma seção da DankBar nas configurações do DMS.

**3. Entre** nos provedores que você usa. O conjunto padrão precisa de:

```bash
command -v bash jq curl codex claude gh
codex login && claude auth status && gh auth status
```

Abra a janela de configurações ⚙ para ativar mais provedores — cada um mostra
se a CLI ou a credencial está pronta.

> [!TIP]
> Associe o painel a um atalho: `dms ipc call aiOverviewControl toggle`.
> Veja todos os comandos em [Uso](./usage.md#ipc-commands).

Prefere um arquivo de release ou um checkout do git? Veja [Instalação](./installation.md).

## 🧩 Provedores

| Cobertura | O que você recebe | Exemplos |
| --- | --- | --- |
| **Cota** | Uso real em % e horário do reset | Codex, Copilot, Antigravity, OpenRouter, Z.ai, GLM, xAI |
| **Saldo** | Crédito pré-pago restante | Kimi, DeepSeek |
| **Analytics** | Tokens, custo e modelos a partir de dados locais | Claude, 9Router, pi, Hermes, Cloudflare |
| **Autenticação** | Checagem de credencial, sem números de uso | Gemini, Mistral, Qwen, Groq, Cohere |
| **Runtime local** | Modelos e sessões locais | Ollama, Vertex AI |
| **Informativo** | Link para a página oficial de uso | Cursor, Kiro, Warp, Perplexity |

A lista completa, as fontes de dados e as credenciais estão em [Provedores](./providers.md).

## 📚 Documentação

O [guia do release 1.20.0](./releases/1.20.0.md) reúne mudanças, privacidade e limitações (em inglês).
Veja também [conversão de custos e privacidade](./currency.md), [módulos de runtime](./refactoring.md)
e [regras de PR e publicação](./repository-rules.md).

A documentação detalhada está em inglês.

| | |
| --- | --- |
| [Uso](./usage.md) | Pílula, popout, cards, teclado, IPC, histórico, privacidade |
| [Instalação](./installation.md) | Loja, arquivo e git; atualizações |
| [Configuração](./configuration.md) | Todas as opções, variáveis de ambiente, checagens |
| [Provedores](./providers.md) | Matriz de cobertura e fontes de dados |
| [Solução de problemas](./troubleshooting.md) | Cards ausentes, credenciais, notificações |
| [Arquitetura](./architecture.md) | Fluxo de execução e contrato dos adaptadores |
| [Traduções](./i18n-crowdin.md) | Idiomas e Crowdin |
| [Contribuindo](../CONTRIBUTING.md) | Checagens locais e convenções |
| [Changelog](../CHANGELOG.md) | Histórico de versões |

## 💜 Apoie o projeto

O [diretório Dank Plugins](https://danklinux.com/plugins) ordena os plugins pelas
reações 👍 na issue de registro de cada um. Uma reação é a coisa mais útil que
você pode fazer — ela decide se outros usuários do DankMaterialShell vão
encontrar o plugin.

<div align="center">

[![Vote no Dank Plugins](https://img.shields.io/badge/Dank%20Plugins-%F0%9F%91%8D%20votar-8B5CF6?style=for-the-badge)](https://github.com/AvengeMedia/dms-plugin-registry/issues/358)
[![Estrela no GitHub](https://img.shields.io/github/stars/bernardopg/AiOverviewControl?style=for-the-badge&color=FFC400&label=estrela)](https://github.com/bernardopg/AiOverviewControl/stargazers)

[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/bernardopg)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white)](https://ko-fi.com/bernardopg)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/wctwom9emu)

</div>

Achou um bug ou tem uma ideia? [Abra uma issue](https://github.com/bernardopg/AiOverviewControl/issues/new/choose).

## 👥 Contribuidores

<div align="center">

<!-- CONTRIBUTORS:START - generated by scripts/render-contributors -->

<a href="https://github.com/bernardopg" title="bernardopg"><img src="https://avatars.githubusercontent.com/u/69475128?v=4&s=112" width="56" height="56" alt="bernardopg" /></a>
<a href="https://github.com/gtheys" title="gtheys"><img src="https://avatars.githubusercontent.com/u/527237?v=4&s=112" width="56" height="56" alt="gtheys" /></a>
<a href="https://github.com/Luna161" title="Luna161"><img src="https://avatars.githubusercontent.com/u/268031236?v=4&s=112" width="56" height="56" alt="Luna161" /></a>
<a href="https://github.com/arqueon" title="arqueon"><img src="https://avatars.githubusercontent.com/u/66568719?v=4&s=112" width="56" height="56" alt="arqueon" /></a>
<a href="https://github.com/goulartdev" title="goulartdev"><img src="https://avatars.githubusercontent.com/u/16469407?v=4&s=112" width="56" height="56" alt="goulartdev" /></a>
<a href="https://github.com/emmsixx" title="emmsixx"><img src="https://avatars.githubusercontent.com/u/56744133?v=4&s=112" width="56" height="56" alt="emmsixx" /></a>
<a href="https://github.com/Murat65536" title="Murat65536"><img src="https://avatars.githubusercontent.com/u/99989538?v=4&s=112" width="56" height="56" alt="Murat65536" /></a>
<a href="https://github.com/gouwazi" title="gouwazi"><img src="https://avatars.githubusercontent.com/u/23072555?v=4&s=112" width="56" height="56" alt="gouwazi" /></a>
<a href="https://github.com/UN-9BOT" title="UN-9BOT"><img src="https://avatars.githubusercontent.com/u/111110804?v=4&s=112" width="56" height="56" alt="UN-9BOT" /></a>
<a href="https://github.com/SkippySteve" title="SkippySteve"><img src="https://avatars.githubusercontent.com/u/69158610?v=4&s=112" width="56" height="56" alt="SkippySteve" /></a>

<!-- CONTRIBUTORS:END -->

Contribuições são bem-vindas — comece por [CONTRIBUTING.md](../CONTRIBUTING.md).

</div>

---

<div align="center">
<sub>Licença MIT · feito com 💜 para a comunidade <a href="https://github.com/AvengeMedia/DankMaterialShell">DankMaterialShell</a></sub>
</div>
