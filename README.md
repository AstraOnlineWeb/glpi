<h1>Implantando o GLPI com o Docker </h1>

**Astra Online**

Para facilitar a vida de muitos, criei uma imagem Docker para o GLPI. Com ela, você pode definir a versão desejada e o fuso horário através de variáveis.

Assumo que você já tenha o Docker instalado e configurado. Caso contrário, siga as instruções da documentação oficial para a instalação.

Link: (https://hub.docker.com/repository/docker/astraonline/glpi).

<h3>Recomendação de servidor</h3>

Ambiente ideal para Docker Swarm é Ubuntu 20.04 com minimo de 4gb de ram com 1 ou 2 nucleos.

<h3>Preparando servidor:</h3>

~~~bash
sudo apt-get update ; apt-get install -y apparmor-utils
 ~~~

<h3>Instalando Docker:</h3>

~~~bash
curl -fsSL https://get.docker.com | bash
~~~

~~~bash
docker swarm init
~~~

<h3>Configurando o ambiente Docker</h3>


~~~bash
docker network create --driver=overlay network_public
~~~

~~~bash
nano traefik.yaml
~~~

<h4>Cole no terminal a configuração do traefik</h4>

~~~bash
version: "3.7"

services:

  traefik:
    image: traefik:2.11.2
    command:
      - "--api.dashboard=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=network_public"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=machineteste24@gmail.com"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--log.level=DEBUG"
      - "--log.format=common"
      - "--log.filePath=/var/log/traefik/traefik.log"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access-log"
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.http-catchall.rule=hostregexp(`{host:.+}`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
        - "traefik.http.routers.http-catchall.priority=1"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "vol_certificates:/etc/traefik/letsencrypt"
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    networks:
      - network_public

volumes:

  vol_shared:
    external: true
    name: volume_swarm_shared
  vol_certificates:
    external: true
    name: volume_swarm_certificates

networks:
  network_public:
    external: true
    name: network_public


~~~

<h4>Execute o conteiner do Traefik</h4>

~~~bash
docker stack deploy --prune --resolve-image always -c traefik.yaml traefik
~~~

<h4>Instalação do Portainer</h4>

~~~bash
nano portainer.yaml
~~~

<h4>Cole no terminal a stack do portainer</h4>

~~~bash
version: "3.7"

services:

  agent:
    image: portainer/agent:2.20.1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.20.1
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=network_public"
        - "traefik.http.routers.portainer.rule=Host(`seudominio.com.br`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  network_public:
    external: true
    attachable: true
    name: network_public

volumes:
  portainer_data:
    external: true
    name: portainer_data
~~~

<h3>Instalando o GLPI em seu Portainer</h3>

Acesse a URL do seu Portainer, acesse a guia Stacks e crie uma nova Stack:

~~~bash
version: "3.7"

services:
  mariadb:
    image: mariadb:latest
    environment:
      MARIADB_ROOT_PASSWORD: Mfcd62!!Mfcd62!!
      MARIADB_DATABASE: glpi
      MARIADB_USER: glpi
      MARIADB_PASSWORD: 1234554321
      TZ: America/Sao_Paulo
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - network_public
    #ports:
    #  - 3307:3306
    restart: always
    deploy:
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: '1'
          memory: 1024M
  
  glpi:
    image: astraonline/glpi:10.0.15
    restart: always
    depends_on:
      - mariadb
    links:
      - "mariadb:mariadb"
    environment:
      TIMEZONE: America/Sao_Paulo
      VERSION: 10.0.2
      UPLOAD_MAX_FILESIZE: 100M
      POST_MAX_FILESIZE: 50M
    volumes:
      - glpi_data:/var/www/html
    networks:
      - network_public
    #ports:
    #  - "8002:80"
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.glpi.rule=Host(`glpi.trecofantastico.com.br`)
        - traefik.http.services.glpi.loadbalancer.server.port=80
        - traefik.http.routers.glpi.service=glpi
        - traefik.http.routers.glpi.tls.certresolver=letsencryptresolver
        - traefik.http.routers.glpi.entrypoints=websecure
        - traefik.http.routers.glpi.tls=true

volumes:
  glpi_data:
    external: true
    name: glpi_data
  mariadb_data:
    external: true
    name: mariadb_data

networks:
  network_public:
    external: true
    name: network_public
~~~

<h3>Criando uma Image Personalizada caso queira mudar a versão ou editar algo</h3>

~~~bash
git clone https://github.com/AstraOnlineWeb/glpi.git
~~~

~~~bash
cd glpi
~~~

~~~bash
docker build -t nomedesuaimage:versao .
~~~

<h3>Para contatos ou Consultoria</h3>

🔔 Esta com dúvidas chama a gente lá no instagram:
👉 Instagram: <ttps://www.instagram.com/astraonlineweeb/>
📱 Whatsapp (61) 99687-8959
👉 Site: <http://astraonline.com.br/>
