## TIPS:

### create tables
```SQL
CREATE USER new_user WITH PASSWORD 'NEW_Password';
CREATE DATABASE cross_chain;
-- switch to the new database
\c cross_chain
GRANT ALL PRIVILEGES ON DATABASE cross_chain TO crosschain;
GRANT ALL PRIVILEGES ON SCHEMA public TO crosschain;
```

### database init

```bash
$ cd crosschain-tasks
$ sudo docker run --rm -it --entrypoint bash 133735975201.dkr.ecr.us-east-1.amazonaws.com/dev/fanstech/crosschain-core:dev-v2-20250711-0919-c838c8f@sha256:a8a100edcb033449148ba5ce99614ab09189c94924a3bf67f19cd330bdd02cf8
$ export DATABASE_URL="postgresql://XXXXX:XXXXXXX@XXXXXXXXXXXX.us-east-1.rds.amazonaws.com:5432/cross_chain?schema=public&connection_limit=20"
$ npx prisma migrate deploy
```