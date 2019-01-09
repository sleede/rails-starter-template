#### copy docker-compose.yml to /apps/@APP_NAME

#### pull images

`docker-compose pull`

#### create/migrate/seed db

`docker-compose run --rm @APP_NAME bundle exec rake db:setup`


#### build assets

`docker-compose run --rm @APP_NAME bundle exec rake assets:precompile`

#### run create and run all services

`docker-compose up -d`

#### restart all services

`docker-compose restart`

#### show services status

`docker-compose ps`

#### update service @APP_NAME, rebuild assets and restart @APP_NAME

```bash
docker-compose pull @APP_NAME
docker-compose stop @APP_NAME
sudo rm -rf public/assets
docker-compose run --rm @APP_NAME bundle exec rake assets:precompile
docker-compose down
docker-compose up -d
```

#### example of command run passing env variables

docker-compose run --rm -e FIXTURES=categories @APP_NAME bundle exec rake ip:fixtures:load

#### edit credentials

docker-compose run --rm -e EDITOR=nano @APP_NAME bundle exec rails credentials:edit