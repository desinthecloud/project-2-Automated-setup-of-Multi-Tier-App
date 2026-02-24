# Project 2: Automated Setup of Multi-Tier Web Application (Bash Provisioning)

Project 2 is the follow-up to Project 1. Same multi-tier application, but the goal is to automate provisioning and configuration using bash scripts so environment setup is repeatable and fast.

## Architecture

| Layer | Service |
|-------|---------|
| Web | Nginx |
| App | Tomcat 8.5.37 |
| Cache | Memcached |
| Messaging | RabbitMQ |
| Database | MariaDB |
| Automation | Bash provisioning scripts wired into Vagrant |

## Prerequisites

- Oracle VM VirtualBox
- Vagrant
- Git Bash or equivalent terminal
- Vagrant plugins:
  ```bash
  vagrant plugin install vagrant-hostmanager
  vagrant plugin install vagrant-vbguest
  ```

## Repo Layout

```text
PROJECT_2/
  Vagrantfile
  provisioning/
    mysql.sh
    tomcat.sh
    nginx.sh
    memcache.sh
    rabbitmq.sh
  application.properties
  README.md
```

---

## Step 1: Provisioning Scripts

### Database (`provisioning/mysql.sh`)

Installs MariaDB, secures the root account, creates the `accounts` database, grants app user permissions, and imports the DB dump from the vprofile repo. Opens port 3306 via firewalld.

```bash
#!/bin/bash
DATABASE_PASS='admin123'
sudo yum update -y
sudo yum install epel-release -y
sudo yum install git zip unzip -y
sudo yum install mariadb-server -y

sudo systemctl start mariadb
sudo systemctl enable mariadb

cd /tmp/
git clone -b local-setup https://github.com/devopshydclub/vprofile-project.git

sudo mysqladmin -u root password "$DATABASE_PASS"
sudo mysql -u root -p"$DATABASE_PASS" -e "UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PASS') WHERE User='root'"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.user WHERE User=''"
sudo mysql -u root -p"$DATABASE_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
sudo mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"
sudo mysql -u root -p"$DATABASE_PASS" -e "create database accounts"
sudo mysql -u root -p"$DATABASE_PASS" -e "grant all privileges on accounts.* TO 'admin'@'localhost' identified by 'admin123'"
sudo mysql -u root -p"$DATABASE_PASS" -e "grant all privileges on accounts.* TO 'admin'@'%' identified by 'admin123'"
sudo mysql -u root -p"$DATABASE_PASS" accounts < /tmp/vprofile-project/src/main/resources/db_backup.sql
sudo mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"

sudo systemctl restart mariadb

sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo firewall-cmd --zone=public --add-port=3306/tcp --permanent
sudo firewall-cmd --reload
sudo systemctl restart mariadb
```

---

### Cache (`provisioning/memcache.sh`)

Installs Memcached and starts it on port 11211.

```bash
#!/bin/bash
sudo yum install epel-release -y
sudo yum install memcached -y
sudo systemctl start memcached
sudo systemctl enable memcached
sudo systemctl status memcached
sudo memcached -p 11211 -U 11111 -u memcached -d
```

---

### Messaging (`provisioning/rabbitmq.sh`)

Installs Erlang and RabbitMQ, creates a `test` user with administrator privileges, and disables the loopback restriction so the app VM can connect.

```bash
#!/bin/bash
sudo yum install epel-release -y
sudo yum update -y
sudo yum install wget -y
cd /tmp/
wget http://packages.erlang-solutions.com/erlang-solutions-2.0-1.noarch.rpm
sudo rpm -Uvh erlang-solutions-2.0-1.noarch.rpm
sudo yum -y install erlang socat
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | sudo bash
sudo yum install rabbitmq-server -y
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server
sudo sh -c 'echo "[{rabbit, [{loopback_users, []}]}]." > /etc/rabbitmq/rabbitmq.config'
sudo rabbitmqctl add_user test test
sudo rabbitmqctl set_user_tags test administrator
sudo systemctl restart rabbitmq-server
```

---

### App (`provisioning/tomcat.sh`)

Installs Java 8 and Maven, downloads and configures Tomcat 8.5.37, builds the WAR artifact, deploys it, and copies `application.properties` into the running deployment.

```bash
TOMURL="https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.37/bin/apache-tomcat-8.5.37.tar.gz"
yum install java-1.8.0-openjdk -y
yum install git maven wget -y
cd /tmp/
wget $TOMURL -O tomcatbin.tar.gz
EXTOUT=`tar xzvf tomcatbin.tar.gz`
TOMDIR=`echo $EXTOUT | cut -d '/' -f1`
useradd --shell /sbin/nologin tomcat
rsync -avzh /tmp/$TOMDIR/ /usr/local/tomcat8/
chown -R tomcat.tomcat /usr/local/tomcat8

cat <<EOT>> /etc/systemd/system/tomcat.service
[Unit]
Description=Tomcat
After=network.target

[Service]
User=tomcat
Group=tomcat
WorkingDirectory=/usr/local/tomcat8
Environment=JAVA_HOME=/usr/lib/jvm/jre
Environment=CATALINA_HOME=/usr/local/tomcat8
ExecStart=/usr/local/tomcat8/bin/catalina.sh run
ExecStop=/usr/local/tomcat8/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl start tomcat
systemctl enable tomcat

git clone -b local-setup https://github.com/devopshydclub/vprofile-project.git
cd vprofile-project
mvn install
systemctl stop tomcat
sleep 60
rm -rf /usr/local/tomcat8/webapps/ROOT*
cp target/vprofile-v2.war /usr/local/tomcat8/webapps/ROOT.war
systemctl start tomcat
sleep 120
cp /vagrant/application.properties /usr/local/tomcat8/webapps/ROOT/WEB-INF/classes/application.properties
systemctl restart tomcat
```

---

### Web (`provisioning/nginx.sh`)

Installs Nginx on Ubuntu and configures it as a reverse proxy forwarding port 80 traffic to Tomcat on app01:8080.

```bash
apt update
apt install nginx -y
cat <<EOT > vproapp
upstream vproapp {
  server app01:8080;
}
server {
  listen 80;
  location / {
    proxy_pass http://vproapp;
  }
}
EOT

mv vproapp /etc/nginx/sites-available/vproapp
rm -rf /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/vproapp /etc/nginx/sites-enabled/vproapp

systemctl start nginx
systemctl enable nginx
systemctl restart nginx
```

---

### Application Properties (`application.properties`)

Vagrant copies this file into the Tomcat deployment so the app can reach each backend service by hostname.

```properties
jdbc.driverClassName=com.mysql.jdbc.Driver
jdbc.url=jdbc:mysql://db01:3306/accounts?useUnicode=true&characterEncoding=UTF-8&zeroDateTimeBehavior=convertToNull
jdbc.username=admin
jdbc.password=admin123

memcached.active.host=mc01
memcached.active.port=11211
memcached.standBy.host=127.0.0.2
memcached.standBy.port=11211

rabbitmq.address=rmq01
rabbitmq.port=5672
rabbitmq.username=test
rabbitmq.password=test
```

---

## Step 2: Wire Scripts into the Vagrantfile

```ruby
config.vm.define "db" do |db|
  db.vm.provision "shell", path: "provisioning/mysql.sh"
end
```

Repeat this pattern for each VM: web, app, cache, and messaging.

---

## Step 3: Bring Up the Environment

```bash
vagrant up
vagrant hostmanager
```

To re-run provisioning only:

```bash
vagrant provision
```

---

## Step 4: Validation

Open your browser and navigate to the web01 IP or hostname. Confirm the following are all working.

- Web application loads and redirects to `/login`
- RabbitMQ management console is accessible
- Memcached is active and responding from the app VM

---

## Troubleshooting

- **DB issues** - confirm the dump import ran and app credentials in `application.properties` match
- **502 from Nginx** - Tomcat is not running or the upstream host/port is wrong
- **RabbitMQ errors** - check the test user exists and the loopback restriction is disabled
- **Memcached** - confirm the listen address is reachable from the app VM

---

## Cleanup

```bash
vagrant halt
vagrant destroy -f
```

---

## What Changed from Project 1

- Full provisioning via bash scripts replaces all manual setup steps
- A single `vagrant up` builds the entire environment from scratch
- Each VM has a dedicated script with clear separation of concerns
- Faster rebuilds when troubleshooting because you can re-provision individual VMs
