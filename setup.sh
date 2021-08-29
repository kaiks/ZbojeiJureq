# docker build --pull --rm -f "Dockerfile" -t zbojeijureq:latest "." <
docker build -t zbojeijureq .

# docker run -it \
#   --name zbojeijureq \
#   --mount source=db,target=/ZbojeiJureq/db \
#   --mount source=logs,target=/ZbojeiJureq/logs \
#   ruby main.rb

### this works at least on windows
docker run -e TZ=Europe/Berlin --mount source=db,target=/ZbojeiJureq/db --mount source=logs,target=/ZbojeiJureq/logs --net=host -p 6667:6667 -it zbojeijureq