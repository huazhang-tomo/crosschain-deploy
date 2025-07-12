## TIPS:

### create tables
```SQL
CREATE USER crosschain WITH PASSWORD 'NEW_Password';
CREATE DATABASE cross_chain;
-- switch to the new database
\c cross_chain
GRANT ALL PRIVILEGES ON DATABASE cross_chain TO crosschain;
GRANT ALL PRIVILEGES ON SCHEMA public TO crosschain;
```

### database init

```bash
$ cd crosschain-tasks
$ sudo docker run --rm -it --entrypoint bash 133735975201.dkr.ecr.us-east-1.amazonaws.com/dev/fanstech/crosschain-core:dev-v2-20250712-0313-4bd4218@sha256:b425ef77ec8f18bc5e27c6d0a84c14c250a6227c22512bbbef8284caf453f41f
$ export DATABASE_URL="postgresql://XXXXX:XXXXXXX@XXXXXXXXXXXX.us-east-1.rds.amazonaws.com:5432/cross_chain?schema=public&connection_limit=20"
$ npx prisma migrate deploy
```