# USER_DOC — Guia do usuário

Documento voltado a quem vai operar a infraestrutura: subir, acessar,
administrar o site e verificar se está tudo funcionando.

Para detalhes de implementação, veja `DEV_DOC.md`.

---

## 1. Antes da primeira execução

### Criar o arquivo de credenciais

O arquivo `srcs/.env` não está no repositório por conter senhas. Crie-o a partir
deste modelo, substituindo os valores entre colchetes:

```bash
cat > srcs/.env << 'EOF'
DOMAIN_NAME=dteruya.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=[senha do usuário do banco]
MYSQL_ROOT_PASSWORD=[senha do root do banco]

WP_TITLE=Inception
WP_ADMIN_USER=dteruya
WP_ADMIN_PASSWORD=[senha do administrador do WordPress]
WP_ADMIN_EMAIL=dteruya@student.42sp.org.br
WP_USER=visitante
WP_USER_PASSWORD=[senha do usuário comum]
WP_USER_EMAIL=visitante@example.com
EOF
```

Duas restrições importantes:

- `WP_ADMIN_USER` **não pode** conter "admin", "Admin" ou "administrator" em
  nenhuma forma. É uma exigência do subject.
- As senhas devem ser definidas antes da primeira subida. Alterá-las depois não
  tem efeito, porque a inicialização só ocorre uma vez — seria necessário
  apagar os volumes e recomeçar.

### Configurar a resolução do domínio

Na máquina onde o site será acessado:

```bash
echo "127.0.0.1 dteruya.42.fr" | sudo tee -a /etc/hosts
```

Se o acesso vier de fora da VM, use o IP da VM no lugar de `127.0.0.1`.

### Criar os diretórios de dados

```bash
mkdir -p /home/dteruya/data/mariadb /home/dteruya/data/wordpress
```

O `make` já faz isso automaticamente, mas vale conferir.

---

## 2. Operação diária

### Iniciar

```bash
make
```

Na primeira execução leva alguns minutos: constrói as imagens, baixa o WordPress
e inicializa o banco. Nas seguintes sobe em segundos, aproveitando o cache.

### Parar

```bash
make down
```

Derruba os containers preservando todos os dados. É o comando para o fim do dia.

### Ver logs

```bash
make logs                  # todos os serviços, em tempo real
docker logs mariadb        # um serviço específico
docker logs wordpress
docker logs nginx
```

### Reiniciar do zero

```bash
make re
```

**Atenção:** apaga todos os dados, incluindo posts, usuários e configurações do
WordPress. Use apenas quando quiser recomeçar de fato.

---

## 3. Acessando o site

| Endereço | Conteúdo |
|---|---|
| `https://dteruya.42.fr` | Site público |
| `https://dteruya.42.fr/wp-admin` | Painel administrativo |

Na primeira visita o navegador exibirá um aviso de certificado não confiável.
Clique em **Avançado** e prossiga. O certificado é auto-assinado por exigência
do subject; o aviso não indica falha.

O acesso por `http://` (porta 80) não funciona, e isso é intencional: apenas a
443 está publicada.

### Contas disponíveis

| Conta | Papel | Onde está definida |
|---|---|---|
| `dteruya` | Administrador | `WP_ADMIN_USER` no `.env` |
| `visitante` | Author | `WP_USER` no `.env` |

O administrador tem acesso total ao painel. O usuário comum pode escrever posts
e comentar, mas não altera configurações do site.

---

## 4. Verificações de saúde

### Os três containers estão de pé?

```bash
docker ps
```

Devem aparecer `nginx`, `wordpress` e `mariadb`, todos com status `Up`. Apenas o
nginx deve mostrar porta publicada (`0.0.0.0:443->443/tcp`).

### O site responde?

```bash
curl -k -s -o /dev/null -w "%{http_code}\n" https://dteruya.42.fr
```

Deve retornar `200`.

### A porta 80 está fechada?

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://dteruya.42.fr
```

Deve falhar na conexão. Se responder algo, há um problema de configuração.

### O TLS está correto?

```bash
openssl s_client -connect dteruya.42.fr:443 -tls1_2 </dev/null 2>/dev/null | grep Protocol
```

Deve indicar TLSv1.2 ou TLSv1.3. Versões anteriores devem ser recusadas.

### O banco tem dados?

```bash
docker exec -it mariadb mariadb -uroot -p"<senha do root>" \
  -e "USE wordpress; SHOW TABLES;"
```

Deve listar as tabelas do WordPress (`wp_posts`, `wp_users`, e outras).

### Os volumes apontam para o lugar certo?

```bash
docker volume ls
docker volume inspect srcs_mariadb_data | grep device
docker volume inspect srcs_wordpress_data | grep device
```

O campo `device` deve conter `/home/dteruya/data/...`.

---

## 5. Testando a persistência

Este é o teste mais importante, e o que a avaliação verifica.

1. Acesse o painel e crie um post ou edite uma página
2. Confirme a alteração no site
3. Reinicie a máquina virtual por completo
4. Suba novamente com `make`
5. Acesse o site — a alteração deve continuar lá

Se os dados desaparecerem, os volumes não estão persistindo corretamente.
Verifique os caminhos com `docker volume inspect`.

---

## 6. Gerenciando credenciais

### Trocar uma senha do WordPress

Pelo painel, em **Usuários**, ou pela linha de comando:

```bash
docker exec -it wordpress wp user update dteruya \
  --user_pass='nova_senha' --allow-root
```

### Trocar senhas do banco

Exige recriar a infraestrutura, pois a inicialização é idempotente:

```bash
make down
# editar srcs/.env com as novas senhas
sudo rm -rf /home/dteruya/data/mariadb/* /home/dteruya/data/wordpress/*
make
```

Isso apaga todo o conteúdo do site. Faça backup antes, se necessário.

### Backup do banco

```bash
docker exec mariadb mariadb-dump -uroot -p"<senha>" wordpress > backup.sql
```

Restauração:

```bash
docker exec -i mariadb mariadb -uroot -p"<senha>" wordpress < backup.sql
```

---

## 7. Problemas comuns

**O navegador não encontra o endereço.**
Falta a entrada em `/etc/hosts`. Confirme com `grep dteruya /etc/hosts`.

**Erro 502 Bad Gateway.**
O nginx está de pé mas não alcança o php-fpm. Verifique se o container
`wordpress` está rodando com `docker ps` e consulte `docker logs wordpress`.

**Erro 403 Forbidden.**
O nginx encontrou o diretório mas não há `index.php`. Normalmente indica que a
instalação do WordPress não completou — veja `docker logs wordpress`.

**O container do WordPress fica repetindo "Aguardando o MariaDB".**
O banco não está aceitando conexões. Teste diretamente:

```bash
docker exec -it wordpress bash -c \
  'mariadb -h mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1"'
```

A mensagem de erro retornada indica a causa.

**Algum container reinicia continuamente.**
Consulte os logs daquele serviço. Como todos usam `restart: always`, uma falha
no processo principal gera um ciclo de reinícios.
