# docker build --pull --rm -f "Dockerfile" -t zbojeijureq:latest "." <
docker build -t zboje .
docker run -it zboje ruby main.rb
