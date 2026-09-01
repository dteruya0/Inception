COMPOSE = docker compose -f srcs/docker-compose.yml

all: up

up:
	@mkdir -p /home/dteruya/data/mariadb /home/dteruya/data/wordpress
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

logs:
	$(COMPOSE) logs -f

clean: down
	$(COMPOSE) down --volumes --remove-orphans

fclean: clean
	@docker system prune -af
	@sudo rm -rf /home/dteruya/data/mariadb/* /home/dteruya/data/wordpress/*

re: fclean all

.PHONY: all up down stop start logs clean fclean re
