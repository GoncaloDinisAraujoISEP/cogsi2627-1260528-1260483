# CA2 - Parte 2: Arquitetura Alternativa ao Vagrant (Multipass com Cloud-Init)

## 1. Visão Geral da Arquitetura

Como alternativa à orquestração baseada em **Vagrant + VirtualBox**, implementou-se uma solução assente em **Multipass** (desenvolvido pela Canonical) em conjunto com provisionamento declarativo através de manifestos **cloud-init** (`#cloud-config`).

A arquitetura mantém a segregação de responsabilidades em três camadas de execução:
- **`db`**: Instância Ubuntu 24.04 com servidor H2 Database Server em modo TCP na porta 9092, gerido via unidade de serviço systemd (`h2.service`) e protegido por regras de firewall UFW.
- **`app`**: Instância com ambiente OpenJDK 17 e Git, alojando a aplicação Spring Boot *Bookstore* configurada como serviço systemd (`bookstore.service`) com reinício automático e injeção da variável de ambiente da base de dados.
- **`proxy`**: Instância de terminação com NGINX configurado como Reverse Proxy na porta 80, realizando o reencaminhamento de tráfego para a camada aplicacional.

A orquestração do cluster foi automatizada através do script PowerShell `up.ps1`, emulando o ciclo de vida simplificado do comando `vagrant up`.

---

## 3. Análise Comparativa: Vagrant vs. Multipass

| Dimensão Técnica | Vagrant (HashiCorp) | Multipass (Canonical) |
| :--- | :--- | :--- |
| **Ecossistema e Suporte a SO** | Agnóstico a SO: suporta distribuições Linux (Debian, RHEL, Alpine), Windows e FreeBSD. | Focado exclusivamente no ecossistema Ubuntu (imagens cloud oficiais da Canonical). |
| **Paradigma de Configuração** | Ficheiro `Vagrantfile` baseado numa DSL imperativa/declarativa em Ruby. | CLI nativa aliada a manifestos declarativos YAML padrão (`cloud-init`). |
| **Topologia de Rede Local** | Suporte nativo e determinístico para redes privadas estáticas (`private_network`) e port-forwarding local. | Alocação prioritária via DHCP; criação de redes internas privadas estáticas requer comutadores de rede avançados no hipervisor anfitrião. |
| **Integração com Produção** | Requer adaptadores ou conversores de provisioners para transição para clouds públicas. | Elevada paridade com ambientes de cloud moderna (AWS, GCP, Azure), partilhando a mesma especificação `cloud-init`. |
| **Overhead e Desempenho** | Arranque mais pesado decorrente da sincronização de pastas partilhadas e módulos de integração do hipervisor. | Lançamento mais ágil em ambientes Hyper-V/KVM, consumindo menor pegada de memória em repouso. |

---

## 4. Avaliação Crítica e Limitações Observadas

Durante a implementação prática sob o sistema operativo Windows com hipervisor VirtualBox, identificaram-se limitações estruturais relevantes:
1. **Isolamento de Rede por Omissão:** Ao contrário do Vagrant, que cria automaticamente adaptadores `Host-Only` com sub-redes partilhadas entre nós, o Multipass sobre VirtualBox atribui interfaces isoladas em modo NAT, exigindo a extração dinâmica de endereços e injeção em `/etc/hosts` para resolução mútua de nós.
2. **Latência de Provisionamento em CLI:** Tarefas de descarregamento e compilação de binários pesados (como o JDK e o repositório aplicacional) no arranque inicial excedem com frequência os tempos de espera síncronos da CLI do Multipass, evidenciando que o Vagrant oferece uma gestão de estado de provisionamento mais resiliente para fluxos de desenvolvimento local.

A conclusão técnica demonstra que o **Vagrant** permanece a ferramenta superior para a orquestração de ambientes multi-nó locais que requerem redes privadas fixas previsíveis, enquanto o **Multipass** se destaca em prototipagem rápida e validação de manifestos de cloud públicos.


lxc list (lista de instancias de clusters)
<img width="955" height="208" alt="image" src="https://github.com/user-attachments/assets/7aee1928-f84a-4733-9219-34dd9916d8b4" />



Provisionamento concluído via Cloud-Init
<img width="865" height="132" alt="image" src="https://github.com/user-attachments/assets/ea208f52-cf49-42cf-b3aa-2361ca0623a3" />

Resposta da Bookstore através do Proxy Reverso
<img width="2024" height="170" alt="image" src="https://github.com/user-attachments/assets/56e13d4a-1c1e-4de0-89e0-a9455c145e7a" />


Consulta de dados na base de dados (/books)
<img width="1206" height="279" alt="image" src="https://github.com/user-attachments/assets/799c87a2-d37a-4ef3-a6d6-44f3726c3a6b" />

Endpoint de saúde (/health)
<img width="856" height="175" alt="image" src="https://github.com/user-attachments/assets/d5f75672-6b1b-4188-8dae-1ddb94bafaf9" />
