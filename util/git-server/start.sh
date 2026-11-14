#!/bin/bash

set -e

REPO_DIR="/tmp/repos/example.git"
if [ ! -d "$REPO_DIR" ]; then
    git init --bare "$REPO_DIR"
    cd "$REPO_DIR"
    git config http.receivepack true  # allow pushes via HTTP
fi

git config --global user.email "you@example.com"
git config --global user.name "Your Name"

TEMP_DIR=$(mktemp -d)
git clone "$REPO_DIR" "$TEMP_DIR"
cd "$TEMP_DIR"
cp -r /git/repo/* .
git add .
git commit -m "Initial commit"
git push origin master
rm -rf "$TEMP_DIR"

mkdir -p /etc/lighttpd

chmod -R 755 /tmp/repos

cat > /etc/lighttpd/lighttpd.conf <<EOF
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_redirect",
    "mod_cgi",
    "mod_setenv"
)

server.document-root = "/tmp/repos"
server.port = 3000
setenv.set-environment = ( "GIT_PROJECT_ROOT" => "/tmp/repos", "GIT_HTTP_EXPORT_ALL" => "" )
alias.url = ( "" => "/usr/libexec/git-core/git-http-backend" )
cgi.assign = ( "" => "" )
EOF

lighttpd -D -f /etc/lighttpd/lighttpd.conf
