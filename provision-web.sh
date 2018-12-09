#!/bin/bash
set -eux

# install node LTS.
# see https://github.com/nodesource/distributions#debinstall
apt-get install -y curl
curl -sL https://deb.nodesource.com/setup_10.x | bash
apt-get install -y nodejs
node --version
npm --version

# add the hello-world user.
groupadd --system hello-world
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup hello-world \
    --home /opt/hello-world \
    hello-world
install -d -o root -g hello-world -m 750 /opt/hello-world

# create an hello world http server and run it as a systemd service.
cat >/opt/hello-world/main.js <<EOF
const http = require("http");

function main(metadata) {
    const server = http.createServer((request, response) => {
        const serverAddress = request.socket.localAddress;
        const clientAddress = request.socket.remoteAddress;
        const message = \`VM Name: \${metadata.compute.name}
Server Address: \${serverAddress}
Client Address: \${clientAddress}
Request URL: \${request.url}
\`; 
        console.log(message);
        response.writeHead(200, {"Content-Type": "text/plain"});
        response.write(message);
        response.end();
    });
    server.listen(3000);
}

// see https://docs.microsoft.com/en-us/azure/virtual-machines/linux/instance-metadata-service#retrieving-all-metadata-for-an-instance
http.get(
    "http://169.254.169.254/metadata/instance?api-version=2017-08-01",
    {
        headers: {
            Metadata: "true"
        }
    },
    (response) => {
        let data = "";
        response.on("data", (chunk) => data += chunk);
        response.on("end", () => {
            const metadata = JSON.parse(data);
            main(metadata);
        });
    }
).on("error", (error) => console.log("Error fetching metadata: " + error.message));
EOF
cat >package.json <<'EOF'
{
  "name": "hello-world",
  "description": "the classic hello world",
  "version": "1.0.0",
  "license": "MIT",
  "main": "main.js",
  "dependencies": {}
}
EOF
npm install

# launch hello-world.
cat >/etc/systemd/system/hello-world.service <<'EOF'
[Unit]
Description=Hello World
After=network.target

[Service]
Type=simple
User=hello-world
Group=hello-world
Environment=NODE_ENV=production
ExecStart=/usr/bin/node main.js
WorkingDirectory=/opt/hello-world
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
systemctl enable hello-world
systemctl start hello-world

# try it.
sleep .2
wget -qO- localhost:3000
