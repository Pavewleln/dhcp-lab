# Минимальный образ для лабораторного DHCP-сервера.
FROM alpine:latest

# dnsmasq выдаёт адреса клиентам из GNS3.
RUN apk add --no-cache dnsmasq

# Работа на переднем плане нужна, чтобы Docker видел процесс и собирал его логи.
ENTRYPOINT ["dnsmasq", "--keep-in-foreground", "--conf-file=/etc/dnsmasq.conf"]
