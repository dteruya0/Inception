*This project has been created as part of the 42 curriculum by dteruya*

# Inception

Infraestrutura de serviços web em containers Docker, orquestrada com docker
compose e executada dentro de uma máquina virtual.

---

## Description

O projeto monta uma stack WordPress completa, com cada serviço isolado em seu
próprio container, construído a partir de uma imagem base do Debian bookworm.

Três serviços compõem a infraestrutura:

| Serviço | Função | Porta |
|---|---|---|
| **nginx** | Servidor web, único ponto de entrada, TLS 1.2/1.3 | 443 (publicada) |
| **wordpress** | WordPress com php-fpm | 9000 (interna) |
| **mariadb** | Banco de dados | 3306 (interna) |

O fluxo de uma requisição:

```
navegador ──443/TLS──> nginx ──9000/FastCGI──> wordpress ──3306──> mariadb
                         │                        │
                         └──── volume compartilhado ────┘
                                 /var/www/html
```

O nginx serve arquivos estáticos diretamente do volume compartilhado e repassa
requisições `.php` ao php-fpm via FastCGI. O WordPress persiste seus dados no
MariaDB, que não é acessível de fora da rede interna do Docker.

Dois volumes garantem persistência entre reinicializações, ambos mapeados para
`/home/dteruya/data/`.

---

## Instructions

### Pré-requisitos

- Máquina virtual com Debian 12 ou similar
- Docker Engine e o plugin docker compose
- Arquivo `srcs/.env` presente (não versionado — ver *Requirements*)
- Entrada `127.0.0.1 dteruya.42.fr` em `/etc/hosts`

### Subir a infraestrutura

```bash
git clone <url-do-repositorio> inception
cd inception
# criar srcs/.env — ver USER_DOC.md
make
```

A primeira execução leva alguns minutos: constrói as três imagens, baixa o
WordPress e inicializa o banco.

### Comandos disponíveis

| Comando | Efeito |
|---|---|
| `make` | Constrói as imagens e sobe os containers |
| `make down` | Derruba os containers, preservando os volumes |
| `make stop` / `make start` | Pausa e retoma sem reconstruir |
| `make logs` | Acompanha os logs em tempo real |
| `make clean` | Derruba containers e remove volumes do compose |
| `make fclean` | Limpeza completa, incluindo os dados em `~/data` |
| `make re` | `fclean` seguido de build completo |

### Acesso

- Site: `https://dteruya.42.fr`
- Painel: `https://dteruya.42.fr/wp-admin`

O navegador exibirá um aviso de certificado não confiável. Isso é esperado: o
certificado é auto-assinado, conforme exigido pelo subject.

---

## Requirements

### Regras respeitadas

- Cada serviço tem seu próprio Dockerfile, construído a partir de
  `debian:bookworm` (penúltima versão estável)
- Nenhuma imagem pronta do Docker Hub é utilizada
- Um único processo em foreground por container, como PID 1
- Sem `tail -f`, `sleep infinity` ou laços infinitos como artifício de PID 1
- Sem `network: host`, sem `links:`, sem `--link`
- Rede bridge dedicada declarada no `docker-compose.yml`
- Apenas o nginx publica porta, exclusivamente a 443, com TLS 1.2/1.3
- Volumes em `/home/dteruya/data/`
- Usuário administrador do WordPress sem "admin" no nome
- Dois usuários no WordPress: um administrador e um author
- Credenciais exclusivamente em variáveis de ambiente
- `restart: always` em todos os serviços

### Sobre as credenciais

O arquivo `srcs/.env` **não está versionado** e consta no `.gitignore`. Ele
concentra as credenciais do banco e do WordPress, e deve ser criado localmente
antes da primeira execução. O modelo está em `USER_DOC.md`.

### Decisões técnicas

**`exec` ao final dos scripts de inicialização.** O `exec` substitui o processo
do shell pelo serviço, em vez de criar um processo filho. Assim o mysqld e o
php-fpm assumem o PID 1 do container e recebem os sinais do Docker diretamente,
permitindo que `docker stop` execute um encerramento limpo.

**Espera ativa pelo MariaDB no WordPress.** O `depends_on` do compose garante
apenas que o container do banco iniciou, não que o mysqld já aceita conexões.
Sem o laço de espera, o `wp core install` falharia por condição de corrida na
primeira execução.

**`bind-address = 0.0.0.0` no MariaDB.** O padrão do MariaDB é escutar apenas em
localhost. Como o WordPress está em outro container, com outro endereço IP, o
banco precisa aceitar conexões de todas as interfaces. Pelo mesmo motivo o
usuário da aplicação é criado como `'wpuser'@'%'`.

**php-fpm em socket TCP na porta 9000.** Sockets unix funcionam apenas entre
processos no mesmo namespace. Com nginx e php-fpm em containers separados, a
comunicação precisa ser por TCP.

**`clear_env = no` no pool do php-fpm.** Sem essa diretiva o php-fpm descarta as
variáveis de ambiente e o WordPress não enxerga as credenciais do banco.

**Testes de idempotência nos scripts de init.** Os volumes persistem entre
execuções. As verificações `[ ! -d /var/lib/mysql/mysql ]` e
`[ ! -f wp-config.php ]` garantem que a instalação ocorre apenas na primeira
subida; nas seguintes o script vai direto ao `exec`.

**Limpeza do datadir no Dockerfile do MariaDB.** O pacote `mariadb-server` do
Debian já popula `/var/lib/mysql` durante a instalação. Sem o `rm -rf` no final
do build, o teste de idempotência nunca seria verdadeiro e o script de
inicialização jamais executaria.

---

## Uso de IA

Neste projeto, a utilização da IA foi fundamental para o avanço do meu conhecimento e para o melhor entendimento dos conceitos envolvidos. Devido ao curto período de tempo que tive para desenvolver o projeto, a IA serviu como uma importante ferramenta de apoio durante o processo de aprendizado, permitindo que eu revisasse os conteúdos de forma mais rápida e aprofundada.

Através desse auxílio, consegui compreender melhor não apenas o que deveria ser desenvolvido no projeto, mas também os conceitos que estão por trás das ferramentas e tecnologias utilizadas. Isso foi especialmente importante para entender o funcionamento do Docker e dos containers, suas finalidades e a forma como eles se relacionam dentro do projeto.

Além de auxiliar na resolução de dúvidas pontuais, a IA também contribuiu para que eu pudesse revisar os conteúdos e validar meu entendimento ao longo do desenvolvimento. Dessa forma, consegui avançar no projeto com uma visão mais clara sobre o que estava sendo feito e, principalmente, compreender os motivos por trás de cada etapa, em vez de apenas seguir instruções ou reproduzir comandos.


---

## Estrutura do repositório

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore
└── srcs/
    ├── .env                    (não versionado)
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/50-server.cnf
        │   └── tools/init.sh
        ├── nginx/
        │   ├── Dockerfile
        │   └── conf/default.conf
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf
            └── tools/init.sh
```
