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
$ sudo docker run --rm -it --entrypoint bash 133735975201.dkr.ecr.us-east-1.amazonaws.com/prod/fanstech/crosschain-core:main-20250819-0941-3f727b5@sha256:95b1b463d15aaa827c667791fa54feed7cc42d91490b273dc9b3b976196948b5
$ export DATABASE_URL="postgresql://XXXXX:XXXXXXX@XXXXXXXXXXXX.us-east-1.rds.amazonaws.com:5432/cross_chain?schema=public&connection_limit=20"
$ npx prisma migrate deploy
```