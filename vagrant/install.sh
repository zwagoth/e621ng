#!/usr/bin/env bash

APP_DIR=/home/danbooru/danbooru
CHRUBY_PATH=/etc/profile.d/chruby.sh

apt-get update

package_installed() {
    if dpkg-query -f '${binary:Package}\n' -W | grep "$1" &>/dev/null; then
        return 0;
    else
        return 1;
    fi
}

add_key() {
    wget -qO - "$1" | sudo apt-key add - &>/dev/null
}

install_packages() {
    sudo apt-get install -y $@
}

script_log() {
    echo "[install.sh] >>> $@"
}

if ! grep danbooru /etc/passwd >/dev/null; then
    script_log "Creating danbooru system user..."
    useradd -m -s /bin/bash -U danbooru
    cp -pr /home/vagrant/.ssh /home/danbooru/
    chown -R danbooru:danbooru /home/danbooru
    echo "%danbooru ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/danbooru
    ln -s /vagrant /home/danbooru/danbooru
    usermod -aG vagrant,www-data danbooru
fi

if ! package_installed elasticsearch; then
    install_packages apt-transport-https default-jre-headless
    add_key https://packages.elastic.co/GPG-KEY-elasticsearch
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" > /etc/apt/sources.list.d/elasticsearch-7.x.list
    script_log "Elasticsearch repository added"
fi

if ! package_installed postgresql-12; then
    add_key https://www.postgresql.org/media/keys/ACCC4CF8.asc
    echo "deb https://apt.postgresql.org/pub/repos/apt/ focal-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    script_log "PostgreSQL repository added"
fi

if ! package_installed nodejs; then
    wget -qO - https://deb.nodesource.com/setup_14.x | sudo -E bash - >/dev/null 2>&1
    script_log "Node.js repository added"
fi

if ! package_installed yarn; then
    add_key https://dl.yarnpkg.com/debian/pubkey.gpg
    echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list
    script_log "yarn repository added"
fi

if ! package_installed redis-server; then
   add-apt-repository -y ppa:redislabs/redis
   script_log "redis repository added"
fi

apt-get update

if ! install_packages \
      build-essential automake libxml2-dev libxslt1-dev yarn nginx libncurses5-dev \
      libreadline-dev flex bison ragel memcached libmemcached-dev git curl \
      libcurl4-openssl-dev nginx ssh libglib2.0-dev \
      mkvtoolnix cmake ffmpeg git postgresql-12 libcurl4-openssl-dev ffmpeg \
      libicu-dev libjpeg-progs libpq-dev libreadline-dev libxml2-dev \
      libexpat1-dev nodejs optipng redis-server postgresql-server-dev-12 \
      liblcms2-dev libjpeg-turbo8-dev libgif-dev libpng-dev libexif-dev \
      elasticsearch; then
    >&2 script_log "Installation of dependencies failed, please see the errors above and re-run \`vagrant provision\`"
    exit 1
fi

script_log "Setting up elasticsearch..."
sed -i -e 's/\(-Xm[sx]\)1g/\1256m/' /etc/elasticsearch/jvm.options
if ! grep -Fq "xpack.security.enabled" /etc/elasticsearch/elasticsearch.yml; then
    echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
fi
systemctl enable elasticsearch 2>/dev/null
service elasticsearch start

script_log "Setting up postgres..."
# allow connections from the host machine
if ! grep -q "192" "/etc/postgresql/12/main/pg_hba.conf"; then
  echo "host danbooru2,danbooru2_test danbooru 192.168.64.1/32 trust" >> /etc/postgresql/12/main/pg_hba.conf
fi
# do not require passwords for authentication
sed -i -e 's/md5/trust/' /etc/postgresql/12/main/pg_hba.conf
# listen for outside connections
echo "listen_addresses = '*'" > /etc/postgresql/12/main/conf.d/listen_addresses.conf

if [ ! -f /usr/lib/postgresql/12/lib/test_parser.so ]; then
    script_log "Building test_parser..."
    pushd .
    git clone https://github.com/r888888888/test_parser.git /tmp/test_parser
    cd /tmp/test_parser
    make install
    popd
    rm -fr /tmp/test_parser
fi

service postgresql restart

script_log "Creating danbooru postgres user..."
sudo -u postgres createuser -s danbooru

if ! type ruby-install >/dev/null 2>&1; then
    script_log "Installing ruby-install..."
    cd /usr/local/src
    wget -qO ruby-install-0.8.1.tar.gz https://github.com/postmodern/ruby-install/archive/v0.8.1.tar.gz
    tar -xzvf ruby-install-0.8.1.tar.gz >/dev/null
    cd ruby-install-0.8.1/
    sudo make install >/dev/null
    rm /usr/local/src/ruby-install-0.8.1.tar.gz

    echo "export RAILS_ENV=development" > /etc/profile.d/rails_env.sh
fi

if [ -f "$CHRUBY_PATH" ]; then
    source $CHRUBY_PATH
fi

if ! type chruby >/dev/null 2>&1; then
    script_log "Installing chruby..."
    cd /usr/local/src
    wget -qO chruby-0.3.9.tar.gz https://github.com/postmodern/chruby/archive/v0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz >/dev/null
    cd chruby-0.3.9/
    sudo make install >/dev/null
    sudo ./scripts/setup.sh >/dev/null
    rm /usr/local/src/chruby-0.3.9.tar.gz

    echo -e \
"if [ -n \"\$BASH_VERSION\" ] || [ -n \"\$ZSH_VERSION\" ]; then
  source /usr/local/share/chruby/chruby.sh
  source /usr/local/share/chruby/auto.sh
fi" > $CHRUBY_PATH
fi

script_log "Installing libvips..."
if ! which vipsthumbnail >/dev/null; then
    VIPS_VERSION=8.10.5
    pushd .
    cd /tmp
    wget -q https://github.com/libvips/libvips/releases/download/v$VIPS_VERSION/vips-$VIPS_VERSION.tar.gz
    tar xf vips-$VIPS_VERSION.tar.gz
    cd vips-$VIPS_VERSION
    ./configure --prefix=/usr
    make install
    ldconfig
    popd
    rm -fr /tmp/vips-$VIPS_VERSION.tar.gz /tmp/vips-$VIPS_VERSION
fi

script_log "Enabling redis server"
systemctl enable redis-server 2>/dev/null
systemctl start redis-server

script_log "Stopping danbooru systemd service..."
service danbooru stop 2>/dev/null

cp /vagrant/vagrant/ruby-setup.sh /home/vagrant/ruby-setup.sh
SETUP_SCRIPT=/home/vagrant/ruby-setup.sh
chmod a+x $SETUP_SCRIPT
sudo -i -u danbooru bash -c "$SETUP_SCRIPT '$APP_DIR' '$CHRUBY_PATH'"

NGINX_CONFIG_PATH=/etc/nginx/conf.d/danbooru.conf
NGINX_DEFAULT_CONFIG_PATH=/etc/nginx/conf.d/default.conf
script_log "Linking nginx config file..."
if [ -f "$NGINX_CONFIG_PATH" ]; then
    rm "$NGINX_CONFIG_PATH"
fi
sudo ln -s $APP_DIR/script/install/nginx.danbooru.conf "$NGINX_CONFIG_PATH"
sed -i -e 's/__hostname__/e621.local/' "$NGINX_CONFIG_PATH"
sed -i -e 's/root \/var\/www\/danbooru\/current\/public;/root \/home\/danbooru\/danbooru\/public;/' "$NGINX_CONFIG_PATH"
if [ -f "$NGINX_DEFAULT_CONFIG_PATH" ]; then
    rm "$NGINX_DEFAULT_CONFIG_PATH"
fi

service nginx restart

script_log "Installing shoreman..."
curl https://github.com/chrismytton/shoreman/raw/master/shoreman.sh -sLo /usr/bin/shoreman
chmod +x /usr/bin/shoreman

script_log "Copying systemd unit file..."
cp $APP_DIR/vagrant/danbooru.service /lib/systemd/system/
systemctl daemon-reload
systemctl enable danbooru 2>/dev/null

script_log "Restarting danbooru systemd service..."
service danbooru restart
