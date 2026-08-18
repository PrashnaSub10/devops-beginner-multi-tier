FROM postgres:16-alpine

ENV POSTGRES_DB=appdb
ENV POSTGRES_USER=appuser
ENV POSTGRES_PASSWORD=secretpassword

COPY init.sql /docker-entrypoint-initdb.d/init.sql

EXPOSE 5432
