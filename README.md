# Dockerizing Your IP Geolocation Service with Nginx Reverse Proxy

[![Build Status](https://travis-ci.org/joemccann/dillinger.svg?branch=master)](https://travis-ci.org/joemccann/dillinger)

![geo-api drawio](https://user-images.githubusercontent.com/68052722/223335486-bba98176-ccd7-46fc-a1ca-4599b5650fd1.png)



### Features
In this tutorial, we will be looking at dockerizing a flask application running an ip-geolocation service, a redis container used for caching and an nginx container configured as a reverse proxy.

**Click [here](https://github.com/sreehariskumar/Launching-a-High-Availability-IP-Geolocation-Application-using-Docker-Swarm.md) to view a high availability model of the same application built using docker swarm.**

| Docker | Version |
| ------ | ------ |
| Client | 20.10.17 |
| Server | 20.10.17 |

### Requirements:
- Docker must be [installed](https://www.docker.com/) and docker daemon running.
- The user running the docker commands may be added to the docker group or else you may need sudo privilege to run the commands. (optional)
- Create an account in [IP Geolocation API](https://ipgeolocation.io/) & copy the API key.
- A self-signed certificate. (Any source can be used)
- A valid domain name.

### Working
- We will be creating a custom bridge to enable name-based communication between containers. All the containers being created will be attached to this bridge.
- The requests are received by an nginx container which is configured as a reverse proxy server which will forward the requests to the configured backend containers.
- We have 3 API containers running a flask application coded to contact the API service provided to fetch and server the details of a provided IP address.
- A data caching service is provided by a redis container.
The API containers first examine the redis container to see if there is any cached information for an IP address when we first request its details. Details are served directly from the redis container if they are present.
- If not, the container makes contact with the API service provider, gathers the data, and then sends it to the redis container to be served and cached.

### AWS Secrets Manager
Follow this [document to create a secret](https://docs.aws.amazon.com/secretsmanager/latest/userguide/create_secret.html) to store your API key. We will be configuring the API container to fetch the key from the secrets manager.

**You will need a project directory to save all your files.
**

```s
mkdir -p ip-geo/{conf,ssl} ; cd ip-geo/
```
The **conf** sub directory is to keep the nginx conf file and the **ssl** sub directory is to keep the self-signed certificates.

### Let’s look at the code of the flask application.
The files can be cloned from this git repository.
```s
git clone https://github.com/sreehariskumar/ip-geo-location-finder.git
```

**Explanation:**
The code sets up a Flask web application that provides the geolocation information of an IP address through an API endpoint. The API calls an external service [ipgeolocation.io](https://ipgeolocation.io/), to retrieve the geolocation information. The API is designed to cache the response from ipgeolocation.io in a Redis database for a specified amount of time (1 hour) to reduce the number of API calls and improve response time.

When the API receives a request for IP geolocation information, it first checks the Redis database for a cached response. If the response is in the cache, the API returns the cached response. If the response is not in the cache, the API calls ipgeolocation.io to retrieve the geolocation information and stores the response in the Redis database with an expiration time of 1 hour. The API then returns the response from ipgeolocation.io.

The **API key** for accessing ipgeolocation.io can be specified as an environment variable or retrieved from [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html).

The code uses the following libraries:
- **os**: provides a way to interact with the underlying operating system, such as reading environment variables.
- **requests**: makes HTTP requests to external APIs.
- **json**: deals with JSON data format.
- **redis**: provides a Python client for interacting with Redis databases.
- **flask**: provides a framework for building and running a web application.
- **boto3**: provides a Python client for interacting with AWS services.

The application can fetch the API key either as plain text from the command line or from the AWS Secrets Manager service. It is ideal to store your sensitive data in any secret manager to ensure security.

```s
cat requirements.txt

requests
redis
flask
boto3
```

**Explanation:**
The required packages are listed in the “requirements.txt” file. These are installed using pip for Python 3.

```s
cat Dockerfile

FROM alpine:3.17
ENV FLASK_PORT 8080
ENV FLASK_DOCUMENTROOT /var/flaskapp
ENV FLASK_USER flaskuser
RUN mkdir -p $FLASK_DOCUMENTROOT    
RUN adduser -h $FLASK_DOCUMENTROOT  -D  -s /bin/sh  $FLASK_USER    
WORKDIR $FLASK_DOCUMENTROOT
COPY .  .
RUN chown -R  $FLASK_USER:$FLASK_USER $FLASK_DOCUMENTROOT
RUN  apk update &&  apk add python3 py3-pip --no-cache
RUN pip3 install -r requirements.txt 
EXPOSE $FLASK_PORT
USER $FLASK_USER
CMD ["app.py"]
ENTRYPOINT ["python3"]
```

**Explanation:**
This Dockerfile has several environment variables to configure the Flask app:
- **FROM alpine:3.17** — specifies the base image used for the build, which is Alpine Linux version 3.17.
- **FLASK_PORT**: sets the port that the Flask app will listen on. This is set to 8080.
- **FLASK_DOCUMENTROOT**: sets the root directory where the Flask app will be stored. This is set to /var/flaskapp.
- **FLASK_USER**: sets the user that the Flask app will run as. This is set to “flaskuser”.
The application is configured under the privilege of this user which eliminates the risk of root privilege for the process running.
- **mkdir -p $FLASK_DOCUMENTROOT**: creates the root directory for the Flask app.
- **adduser -h $FLASK_DOCUMENTROOT -D -s /bin/sh $FLASK_USER**: creates the user for the Flask app.
- **WORKDIR $FLASK_DOCUMENTROOT**: sets the current working directory to the root directory of the Flask app.
- **COPY . .**: copies all the files in the current directory to the current working directory within the Docker image.
- **chown -R $FLASK_USER:$FLASK_USER $FLASK_DOCUMENTROOT**: sets the owner and group of the Flask app files to the "flaskuser".
- **apk update && apk add python3 py3-pip --no-cache**: updates the Alpine package index and installs Python 3 and pip for Python 3.
- **pip3 install -r requirements.txt**: installs the packages listed in the "requirements.txt" file using pip for Python 3.

The Dockerfile then uses the **EXPOSE** command to specify the port that the Flask app will listen on. In this case, the port is specified using the **FLASK_PORT** environment variable.

The **USER** instruction sets the default user to run the app as. In this case, the user is specified using the **FLASK_USER** environment variable. It matters where you put this instruction because any instructions you issue after defining the USER instruction will only be able to be executed by this user, not as root.

Finally, **CMD** and **ENTRYPOINT** commands specify the default command to run the app. The **CMD** command specifies "app.py" as the file to run, and the **ENTRYPOINT** command specifies "python3" as the interpreter to run the file with.

In summary, this Dockerfile sets up an Alpine Linux-based Docker image to run a Flask app, specifying its configuration, dependencies, and default command to run.

**Let’s run a temporary nginx container to get the nginx configuration file.
**
```s
docker container run --name nginx-temp -d --rm nginx:alpine
```

The [docker run](https://docs.docker.com/engine/reference/commandline/run/) command will pull an nginx:alpine image first if not present locally, and then runs a container.
As this is a temporary container, the **-rm** lag is defined to remove the container when it exits.

```s
docker container exec nginx-temp ls -l /etc/nginx/conf.d/

total 4
-rw-r--r--    1 root     root          1093 Feb  2 05:36 default.conf
```

The [docker exec](https://docs.docker.com/engine/reference/commandline/exec/) is used to run a command in a running container. We run **ls -l** command to list the configuration file.
We will be choosing the **default.conf** file located at **/etc/nginx/conf.d/** location of the container.

```s
docker container cp nginx-temp:/etc/nginx/conf.d/default.conf ./conf/.
```

The [docker cp](https://docs.docker.com/engine/reference/commandline/cp/) command is used to copy files/folders between a container and the local filesystem.
Here, we copy the configuration file from the container to our project directory in our local system.

### What is the difference between nginx.conf file and default.conf file?
The **nginx.conf** file is the main configuration file for Nginx and is typically located at **/etc/nginx/nginx.conf**. This file contains the global settings for Nginx and is used to configure how Nginx behaves overall.

The **default.conf** file, on the other hand, is a server block configuration file that is usually stored in the **/etc/nginx/conf.d/** directory. This file is used to specify the behaviour of a particular virtual host or server block, and it contains settings such as the server name, listen to addresses and ports, and reverse proxy configurations.

```s
docker container stop nginx-temp
```

We can stop the container with the [docker stop](https://docs.docker.com/engine/reference/commandline/stop/) command. The container will be removed automatically as we’ve mention --rm flag during creation.

### Let’s begin by creating a custom bridge.

```s
docker network create geo-net

docker network ls 
```

### Let’s run the redis container first.

```s
docker container run -d --name geo-redis --restart always --network geo-net redis:latest
```

The **geo-redis** container will be constructed with the restart policy set to **always**, which ensures that it will always start back up after being stopped. Additionally, the **geo-net** custom bridge network will be attached to the container.

```s
docker container ls -a
CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS      NAMES
115cb58ed643   redis:latest   "docker-entrypoint.s…"   30 seconds ago   Up 29 seconds   6379/tcp   geo-redis
```

### Attaching Role to an EC2 instance.
You will need to create and attach a role with a **custom policy** to have read privilege over your stored secret.

```s
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds"
            ],
            "Resource": "arn:aws:secretsmanager:xxxxxxxxxx"
        },
        {
            "Effect": "Allow",
            "Action": "secretsmanager:ListSecrets",
            "Resource": "*"
        }
    ]
}
```

Although this policy can list all secrets, it only has read access to your secret.
Follow the [instructions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#attach-iam-role) mentioned in the document on attaching a role to an EC2 instance.

### Now, it is time to spin up the API containers.
```s
docker container run -d --name geo-api-1 --restart always -e REDIS_PORT="6379" -e REDIS_HOST="geo-redis" -e APP_PORT="8080" -e API_KEY_FROM_SECRETSMANAGER="True" -e SECRET_NAME="xxxxx" -e SECRET_KEY="xxxxx" -e REGION_NAME="xxxxx" --network geo-net sreehariskumar/ip-geo-location-finder:latest
```

**Explanation:**
- **docker container run** is the command to run a new container.
- **-d** runs the container in the background as a daemon.
- **--name geo-api-1** gives the container the name "geo-api-1".
- **--restart always** specifies that the container should always restart, even if it exits or crashes.
- **-e REDIS_PORT="6379"** and **-e REDIS_HOST="geo-redis"** set environment variables in the container. In this case, **REDIS_PORT** is set to 6379, and **REDIS_HOST** is set to "geo-redis".
- **-e APP_PORT="8080"** sets the application to run on port 8080.
- **-e API_KEY_FROM_SECRETSMANAGER="True"** sets the application to fetch the API key from the AWS Secrets Manager.
- **-e SECRET_NAME="xxxxx"** and **-e SECRET_KEY="xxxxx"** defines the secret name and the secret key to fetch out the secret.
- **-e REGION_NAME="xxxxx"** defines the region of our stored secret.
- **--network geo-net** attaches the container to a Docker network named "geo-net".
- **sreehariskumar/ip-geo-location-finder:latest** is the image name and tag used to run the container.
- Similarly, let’s create two more of these containers under different names.

```s
docker container run -d --name geo-api-2 --restart always -e REDIS_PORT="6379" -e REDIS_HOST="geo-redis" -e APP_PORT="8080" -e API_KEY_FROM_SECRETSMANAGER="True" -e SECRET_NAME="xxxxx" -e SECRET_KEY="xxxxx" -e REGION_NAME="xxxxx" --network geo-net sreehariskumar/ip-geo-location-finder:latest
```
```s
docker container run -d --name geo-api-3 --restart always -e REDIS_PORT="6379" -e REDIS_HOST="geo-redis" -e APP_PORT="8080" -e API_KEY_FROM_SECRETSMANAGER="True" -e SECRET_NAME="xxxxx" -e SECRET_KEY="xxxxx" -e REGION_NAME="xxxxx" --network geo-net sreehariskumar/ip-geo-location-finder:latest
```

### Self-Signed Certificate
I'm using [this](https://getacert.com/selfsignedcert.html) website for the creating a self-signed certificate. You can choose any website of your choice.

Once you'ce provided the details, you can download the certificate and key file:

```s
wget https://getacert.com/ca/certs/wild.1by2.online-2023-02-02-071920.cer -O ./ssl/wild.1by2.online.cer
```
```s
wget https://getacert.com/ca/certs/wild.1by2.online-2023-02-02-071920.pkey -O wild.1by2.online.key
```

### Now, let’s modify the nginx as a reverse proxy.

```s
cat default.conf

server { 
  listen 80;
  listen [::]:80;
  server_name geolocation-api.1by2.online;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  ssl_sertificate /etc/nginx/ssl/wild.1by2.online.cer;
  ssl_certificate_key /etc/nginx/ssl/wild.1by2.online.key;
  server_name geolocation-api.1by2.online;
  
  location / {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwareded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_pass http://geo-api;
  }
}

upstream geo-api {
  server geo-api-1:8080;
  server geo-api-2:8080;
  server geo-api-3:8080;
}
```

**Explanation:**
- This is how we configure the Nginx container to serve HTTP requests.
- The first server block **listens** on ports 80 and 443 for both IPv4 and IPv6 addresses and is used to redirect HTTP requests to HTTPS by returning a 301 redirect status code to the client.
- The second server block **listens** on ports 443 (using SSL) and serves HTTPS requests. It also sets up an SSL certificate and key files for encryption and specifies the server name.
- Within the second server block, the **location** block sets up a reverse proxy to forward incoming requests to an upstream server group **geo-api**(any name can be used), which consists of three servers **geo-api-1**, **geo-api-2**, and **geo-api-3**, running on port 8080. The **proxy_set_header** directives set header values in the proxied request.
- An **upstream** group is used to define a set of backend servers that will receive requests from Nginx. Nginx will forward incoming requests to one of the servers in this upstream group based on the load-balancing algorithm specified in the Nginx configuration.

### Advantages of using Nginx over Application Load Balancer
- **Flexibility**: Nginx provides a wide range of configuration options and can be used for various purposes beyond load balancing, such as caching, request redirection, and SSL termination.
- **Performance**: Nginx has a smaller memory footprint and can handle a large number of connections, making it suitable for high-traffic websites.
- **Cost**: Nginx is open-source software and free to use, whereas the Application Load Balancer service is a paid service offered by AWS.
- **Control**: By using Nginx, you have full control over the configuration and behaviour of the reverse proxy, which can be important for certain use cases where customization is required.
- **Portability**: Nginx can be deployed on various platforms and operating systems, making it easy to move between different environments.

_It is important to note that both Nginx and Application Load Balancer have their own strengths and weaknesses, and the choice between the two ultimately depends on the specific requirements of your application and infrastructure._

### Launching the Nginx container
```s
docker container run -d --name proxy -v $(pwd)/conf/default.conf:/etc/nginx/conf.d/default.conf -v $(pwd)/ssl:/etc/nginx/ssl -p 80:80 -p 443:443  --network geo-net nginx:alpine
```
```s
docker container ls -a

CONTAINER ID   IMAGE                                          COMMAND                  CREATED             STATUS              PORTS                                                                      NAMES
552692ca74fd   nginx:alpine                                   "/docker-entrypoint.…"   17 minutes ago      Up 17 minutes   0.0.0.0:80->80/tcp, :::80->80/tcp, 0.0.0.0:443->443/tcp, :::443->443/tcp   proxy
24f839351127   sreehariskumar/ip-geo-location-finder:latest   "python3 app.py"         19 minutes ago      Up 19 minutes   8080/tcp                                                                   geo-api-3
03f33d6da5be   sreehariskumar/ip-geo-location-finder:latest   "python3 app.py"         19 minutes ago      Up 19 minutes   8080/tcp                                                                   geo-api-2
971877efa1f8   sreehariskumar/ip-geo-location-finder:latest   "python3 app.py"         19 minutes ago      Up 19 minutes   8080/tcp                                                                   geo-api-1
115cb58ed643   redis:latest                                   "docker-entrypoint.s…"   25 minutes ago      Up 25 minutes   6379/tcp                                                                   geo-redis
```

**Explanation:**
- **-d**: Run the container in the background.
- **--name proxy**: Name the container "proxy".
- **-v $(pwd)/conf/default.conf:/etc/nginx/conf.d/default.conf**: Mount the local file "default.conf" in the "conf" directory to the "/etc/nginx/conf.d/default.conf" file in the container.
- **-v $(pwd)/ssl:/etc/nginx/ssl**: Mount the local "ssl" directory to the "/etc/nginx/ssl" directory in the container.
- **-p 80:80**: Map the host's port 80 to the container's port 80.
- **-p 443:443**: Map the host's port 443 to the container's port 443.
**(Both ports are published to handle HTTP & HTTPS requests)**
- **--network geo-net**: Attach the container to the "geo-net" network to enable name-based communication between the containers.

_In short, this command creates a Docker container running Nginx, maps the host’s ports 80 and 443 to the container’s ports, and mounts the local “conf” and “ssl” directories to the container’s “/etc/nginx” directory._

### Adding record in Route53
Create a record pointing to the ip address of the instance to access the application publicly.
I've given **geolocation-api.1by2.online**
Follow the [document](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-creating.html) for creating a record in Route53.

### Finally, try accessing the application.
=> _http://geolocation-api.1by2.online/ip/8.8.8.8_

You can **ignore** the warning as we’re using self-signed certificate here.

### Result
As you could see, the HTTP request has been redirected to HTTPS. Also, you could see the details of the IP address that we’ve provided. You could see that the highlighted portion mentions the value **“cached”: “False”**.
The **"apiServer”** value displays the ID of the container serving the data. Please note the **“apiServer”** value here.

If you refresh the page, you could see **“cached”: “True”**, which means the value has been cached this time.
Also, the **“apiServer”** value is different this time. (The request has been redirected to another container this time by the nginx container.)



**I hope you were able to follow. Hope that it might help you guys.
Please share your reviews.**
