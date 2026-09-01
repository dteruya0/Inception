# DEV_DOC — Guia do desenvolvedor

Documentação técnica da infraestrutura: como está construída, por que cada
decisão foi tomada, e como modificá-la.

Para operação do dia a dia, veja `USER_DOC.md`.

---

## 1. Pré-requisitos

| Requisito | Versão usada |
|---|---|
| Sistema operacional (VM) | Debian 12 bookworm |
| Docker Engine | 20.10+ |
| docker compose | plugin v2 |
| GNU Make | qualquer versão recente |

O projeto foi desenvolvido e testado em uma VM QEMU/KVM com 4 GB de RAM e
2 vCPUs. VirtualBox também funciona, desde que a versão seja compatível com o
kernel do host.

### Instalação do Docker no Debian

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg make git

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian bookworm stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update && sudo apt install -y docker-ce docker-ce-cli \
    containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
```

O grupo `docker` só passa a valer em uma sessão nova — faça logout e login.

---

## 2. Estrutura do projeto

```
.
├── Makefile                 alvos de build e ciclo de vida
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore               ignora srcs/.env
└── srcs/
    ├── .env                 credenciais (não versionado)
    ├── docker-compose.yml   orquestração
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/50-server.cnf    configuração do servidor
        │   └── tools/init.sh         entrypoint
        ├── nginx/
        │   ├── Dockerfile
        │   └── conf/default.conf     virtual host TLS
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf         pool do php-fpm
            └── tools/init.sh         entrypoint
```

A separação `conf/` e `tools/` é exigida pelo subject. Ela mantém arquivos de
configuração estáticos separados de scripts executáveis, o que facilita
auditoria e evita que um `COPY` acidental traga lixo para a imagem.

---

## 3. Arquitetura

### Fluxo de uma requisição

```
1. Navegador abre https://dteruya.42.fr
2. nginx encerra o TLS na porta 443
3. Se o recurso for estático, nginx serve do volume compartilhado
4. Se for .php, nginx repassa via FastCGI para wordpress:9000
5. php-fpm executa o PHP, consultando mariadb:3306 quando necessário
6. Resposta percorre o caminho inverso
```

### Rede

Uma rede bridge dedicada, `inception`, é criada pelo compose. O DNS interno do
Docker resolve os nomes dos serviços, o que permite referências como
`fastcgi_pass wordpress:9000` e `mariadb -h mariadb` sem endereços fixos.

É por isso que `links:` e `network: host` são desnecessários — e proibidos pelo
subject. A resolução por nome já é nativa em redes bridge customizadas.

### Volumes

| Volume | Ponto de montagem | Serviços |
|---|---|---|
| `mariadb_data` | `/var/lib/mysql` | mariadb |
| `wordpress_data` | `/var/www/html` | wordpress, nginx |

Ambos usam `driver_opts` com `type: none` e `o: bind`, apontando para
`/home/dteruya/data/`. Essa construção declara um volume nomeado que na prática
é um bind mount, atendendo à exigência do subject sobre a localização dos dados.

O volume do WordPress é compartilhado entre dois containers porque o nginx
precisa ler os arquivos estáticos (CSS, JS, imagens) diretamente, sem passar
pelo PHP.

---

## 4. Detalhamento dos serviços

### MariaDB

**Base:** `debian:bookworm` + pacote `mariadb-server`

**Configuração** (`conf/50-server.cnf`):
- `bind-address = 0.0.0.0` — sem isso o servidor escuta apenas em localhost e
  o WordPress, que está em outro container, não consegue conectar
- `skip-name-resolve` — evita lookups DNS reversos a cada conexão

**Entrypoint** (`tools/init.sh`):

1. Verifica se `/var/lib/mysql/mysql` existe. Se existir, pula direto ao passo 6
2. Executa `mysql_install_db` para criar as tabelas de sistema
3. Sobe um servidor temporário com `--skip-networking`, inacessível de fora
4. Aplica o SQL: cria o banco, o usuário da aplicação e define a senha do root
5. Encerra o servidor temporário e aguarda seu término
6. `exec mysqld --user=mysql`

**Ponto de atenção no Dockerfile:** o pacote `mariadb-server` do Debian já
popula `/var/lib/mysql` durante a instalação. Sem a limpeza no final do build,
a verificação do passo 1 nunca seria verdadeira e a inicialização jamais
executaria:

```dockerfile
RUN rm -rf /var/lib/mysql/* \
    && mkdir -p /var/run/mysqld /var/lib/mysql \
    && chown -R mysql:mysql /var/run/mysqld /var/lib/mysql
```

**Outro ponto de atenção:** a partir do MariaDB 10.4, `mysql.user` deixou de ser
uma tabela e passou a ser uma view não atualizável. Comandos como
`DELETE FROM mysql.user WHERE User=''` falham e abortam o lote SQL inteiro. Para
remover usuários anônimos, use `DROP USER IF EXISTS ''@'localhost'`.

### WordPress

**Base:** `debian:bookworm` + php8.2-fpm e extensões + wp-cli

**Configuração** (`conf/www.conf`):
- `listen = 9000` — socket TCP em vez do socket unix padrão, já que nginx e
  php-fpm estão em containers distintos
- `clear_env = no` — sem isso o php-fpm descarta as variáveis de ambiente e o
  WordPress não enxerga as credenciais do banco

**Entrypoint** (`tools/init.sh`):

1. Aguarda o MariaDB aceitar conexões, testando em laço a cada 2 segundos
2. Se `wp-config.php` já existe, pula ao passo 7
3. `wp core download`
4. `wp config create` com as credenciais do ambiente
5. `wp core install` com título, URL e conta de administrador
6. `wp user create` para o usuário comum
7. `exec php-fpm8.2 -F`

**Por que o laço de espera:** o `depends_on` do compose garante apenas que o
container do MariaDB foi iniciado, não que o processo dentro dele já está
pronto. Sem a espera, o `wp core install` falharia na primeira execução por
condição de corrida.

**Por que `-F`:** o php-fpm daemoniza por padrão. Se o processo principal for
para background, o container encerra imediatamente.

### NGINX

**Base:** `debian:bookworm` + nginx e openssl

O certificado auto-assinado é gerado durante o build, usando `DOMAIN_NAME` como
build arg para preencher o campo CN.

**Configuração** (`conf/default.conf`):
- `listen 443 ssl` — única porta em escuta
- `ssl_protocols TLSv1.2 TLSv1.3` — exigência explícita do subject
- `fastcgi_pass wordpress:9000` — resolução pelo DNS interno do Docker
- `try_files $uri $uri/ /index.php?$args` — permalinks do WordPress

O site padrão do Debian é removido no build (`rm -f
/etc/nginx/sites-enabled/default`) para que nada escute na porta 80.

**Por que `daemon off;`:** mesmo motivo do `-F` no php-fpm. O nginx precisa
permanecer em foreground para o container continuar vivo.

---

## 5. O Makefile

```makefile
COMPOSE = docker compose -f srcs/docker-compose.yml
```

| Alvo | Ação |
|---|---|
| `all` / `up` | Cria os diretórios de dados e sobe com `--build` |
| `down` | Derruba containers, preserva volumes |
| `stop` / `start` | Pausa e retoma sem reconstruir |
| `logs` | `logs -f` de todos os serviços |
| `clean` | `down --volumes --remove-orphans` |
| `fclean` | `clean` + `system prune -af` + remoção de `~/data/*` |
| `re` | `fclean` seguido de `all` |

**Cuidado ao editar:** as linhas de comando de um Makefile precisam começar com
TAB, nunca com espaços. Um editor configurado para expandir tabs quebra o
arquivo silenciosamente.

**Nota sobre o `fclean`:** a remoção dos dados usa `sudo rm -rf`. Se o sudo
pedir senha em um contexto não interativo, a limpeza pode falhar sem sinalizar.
Ao suspeitar disso, verifique com `ls -la ~/data/mariadb` e remova manualmente
se necessário.

---

## 6. Persistência

Os dados sobrevivem a três situações distintas:

| Operação | Containers | Volumes | Dados |
|---|---|---|---|
| `make down` | removidos | preservados | preservados |
| Reboot da VM | recriados | preservados | preservados |
| `make fclean` | removidos | removidos | **apagados** |

Os scripts de inicialização são idempotentes por design: verificam se a
instalação já ocorreu antes de executá-la. Sem isso, cada reinício recriaria o
banco e apagaria o conteúdo do site.

### Verificação

```bash
docker volume inspect srcs_mariadb_data | grep device
docker volume inspect srcs_wordpress_data | grep device
```

Ambos devem apontar para `/home/dteruya/data/`.

---

## 7. Modificando a configuração

### Alterar a porta publicada

Edite a seção `ports` do serviço nginx em `srcs/docker-compose.yml`:

```yaml
    ports:
      - "8443:443"
```

O primeiro número é a porta no host; o segundo é a porta dentro do container.
Alterar apenas o primeiro não exige mudanças no nginx.

Para mudar também a porta interna, edite `listen` em `conf/default.conf` e o
`EXPOSE` do Dockerfile, mantendo a coerência com o mapeamento.

Depois:

```bash
make down && make
```

### Alterar a versão do PHP

Edite os nomes dos pacotes no Dockerfile do WordPress, o caminho do `www.conf`
e o binário no `exec` do entrypoint. Os três precisam concordar.

### Adicionar um serviço

1. Crie `srcs/requirements/<serviço>/` com `Dockerfile`, `conf/` e `tools/`
2. Declare o serviço no `docker-compose.yml`, na rede `inception`
3. Adicione um volume se o serviço precisar persistir dados
4. Não publique portas além da 443, salvo quando o serviço exigir

---

## 8. Depuração

### Comandos úteis

```bash
docker ps -a                    # inclui containers parados
docker logs <serviço>           # saída do container
docker exec -it <serviço> bash  # shell dentro do container
docker inspect <serviço>        # configuração completa em JSON
docker network inspect srcs_inception
docker compose -f srcs/docker-compose.yml config   # valida o YAML
```

### Testar conectividade entre containers

```bash
docker exec -it wordpress bash -c \
  'mariadb -h mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1"'
```

Um erro 1130 indica que o usuário não existe ou não tem permissão para o host de
origem. Um erro de conexão recusada sugere que o mysqld não está escutando na
interface correta.

### Verificar variáveis de ambiente

```bash
docker exec -it mariadb env | grep MYSQL
```

Se as variáveis não aparecerem, o `env_file` não foi aplicado.

### Confirmar o PID 1

```bash
docker exec -it mariadb ps -p 1 -o comm=
```

Deve retornar `mariadbd`, não `bash` ou `sh`. Se retornar um shell, o `exec` não
está sendo usado corretamente no entrypoint.

### Dica sobre laços de espera

Scripts de espera costumam usar `&>/dev/null` para silenciar tentativas
falhas — o que também esconde a mensagem de erro real. Ao investigar um
container preso em espera, execute o comando manualmente, sem o redirecionamento.

---

## 9. Referências rápidas

**Ver as camadas de uma imagem** (útil para provar que foi construída
localmente, e não baixada do Docker Hub):

```bash
docker history nginx
```

**Verificar o protocolo TLS negociado:**

```bash
openssl s_client -connect dteruya.42.fr:443 -tls1_2 </dev/null 2>/dev/null \
  | grep -E "Protocol|Cipher"
```

**Confirmar que nada escuta na porta 80:**

```bash
docker exec -it nginx ss -tlnp 2>/dev/null || \
  docker exec -it nginx netstat -tlnp
```
