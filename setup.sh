docker container rm -f zbojeijureq
docker build -t zbojeijureq .

# check if we're on windows
if [[ "$(uname)" =~ NT ]]; then
    echo "Windows detected"
    export MSYS_NO_PATHCONV=1
    container_path="$(pwd)"
    echo "Container path: $container_path"
    docker run -e TZ=Europe/Berlin -v "$container_path/db":"/ZbojeiJureq/db":Z -v "$container_path/logs":"/ZbojeiJureq/logs":Z -v "$HOME/www/logs":"/log_upload":Z --net=host --restart unless-stopped --name zbojeijureq -it zbojeijureq
else
    docker run -e TZ=Europe/Berlin --mount source=db,target=/ZbojeiJureq/db --mount source=logs,target=/ZbojeiJureq/logs --mount source=$HOME/www/logs,target=/log_upload --net=host --restart unless-stopped --name zbojeijureq -it zbojeijureq
fi