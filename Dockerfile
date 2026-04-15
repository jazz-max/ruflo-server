FROM node:22-alpine

RUN apk add --no-cache curl bash postgresql-client

RUN npm install -g ruflo@latest pg supergateway

ENV RUFLO_PORT=3000
ENV POSTGRES_HOST=postgres
ENV POSTGRES_PORT=5432
ENV POSTGRES_DB=ruflo
ENV POSTGRES_USER=ruflo
ENV POSTGRES_PASSWORD=ruflo

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app

EXPOSE ${RUFLO_PORT}

ENTRYPOINT ["/entrypoint.sh"]
