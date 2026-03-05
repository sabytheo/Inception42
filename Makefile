LOGIN   = tsaby
DATA    = /home/$(LOGIN)/data
COMPOSE = docker compose -f srcs/docker-compose.yml

all: setup
	$(COMPOSE) up --build -d

setup:
	@mkdir -p $(DATA)/wordpress $(DATA)/mariadb

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

clean: down
	docker system prune -af --volumes

fclean: clean
	sudo rm -rf $(DATA)

re: fclean all

.PHONY: all setup down stop clean fclean re
