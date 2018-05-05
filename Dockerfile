FROM debian:jessie-backports

ARG MOD_AUTH_OPENIDC=libapache2-mod-auth-openidc_2.3.3-1.jessie.1_amd64.deb
RUN apt-get update && apt-get install -y apache2 libjansson4 libhiredis0.10 libcurl3 libcjose0 wget && \
	wget "https://github.com/zmartzone/mod_auth_openidc/releases/download/v2.3.3/$MOD_AUTH_OPENIDC" && \
	dpkg -i "$MOD_AUTH_OPENIDC" && \
	rm -r /var/lib/apt/lists/*

ADD proxy.conf /etc/apache2/sites-available/000-default.conf
ADD run-proxy.sh /
RUN ln -sf /etc/apache2/mods-available/auth_openidc.load /etc/apache2/mods-enabled/ && \
	ln -sf /etc/apache2/mods-available/proxy.load /etc/apache2/mods-enabled/ && \
	ln -sf /etc/apache2/mods-available/proxy_http.load /etc/apache2/mods-enabled/ && \
	ln -sf /etc/apache2/mods-available/headers.load /etc/apache2/mods-enabled/ && \
	chmod 0755 /run-proxy.sh
		
CMD [ "/run-proxy.sh" ]
