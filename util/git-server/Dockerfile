FROM cgr.dev/chainguard/wolfi-base

RUN apk add git git-daemon bash lighttpd

EXPOSE 3000

COPY start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
