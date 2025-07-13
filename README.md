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
$ sudo docker run --rm -it --entrypoint bash 133735975201.dkr.ecr.us-east-1.amazonaws.com/dev/fanstech/crosschain-core:dev-v2-20250713-1157-1329440@sha256:f3c980a2f2a3c0064760d9b57c97bc519cb3f20bdd09d1e7dd4465994639288c
$ export DATABASE_URL="postgresql://XXXXX:XXXXXXX@XXXXXXXXXXXX.us-east-1.rds.amazonaws.com:5432/cross_chain?schema=public&connection_limit=20"
$ npx prisma migrate deploy
```