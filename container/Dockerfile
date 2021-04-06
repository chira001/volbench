FROM bash:latest

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
	fio

COPY volbench.sh /
CMD ["bash","/volbench.sh"]
 
