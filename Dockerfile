FROM node:22-alpine

RUN apk add --no-cache curl bash postgresql-client

RUN npm install -g ruflo@latest pg supergateway

ENV RUFLO_PORT=3000
ENV POSTGRES_HOST=localhost
ENV POSTGRES_PORT=5432
ENV POSTGRES_DB=ruflo
ENV POSTGRES_USER=ruflo
ENV POSTGRES_PASSWORD=ruflo

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app

EXPOSE ${RUFLO_PORT}

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD node -e "const s=require('net').createConnection({port:process.env.RUFLO_PORT||3000,host:'127.0.0.1'},()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1))"

ENTRYPOINT ["/entrypoint.sh"]
