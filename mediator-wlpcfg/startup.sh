#!/bin/bash

# Configure amalgam8 for this container
export A8_SERVICE=mediator:v1
export A8_ENDPOINT_PORT=9443
export A8_ENDPOINT_TYPE=https


if [ "$SERVERDIRNAME" == "" ]; then
  SERVERDIRNAME=defaultServer
else
  # Share the configuration directory via symlink
  ln -s /opt/ibm/wlp/usr/servers/defaultServer /opt/ibm/wlp/usr/servers/$SERVERDIRNAME

  # move the convenience output dir link to the new output location
  rm /output
  ln -s $WLP_OUTPUT_DIR/$SERVERDIRNAME /output
fi

if [ "$ETCDCTL_ENDPOINT" != "" ]; then
  echo Setting up etcd...
  echo "** Testing etcd is accessible"
  etcdctl --debug ls
  RC=$?

  while [ $RC -ne 0 ]; do
      sleep 15

      # recheck condition
      echo "** Re-testing etcd connection"
      etcdctl --debug ls
      RC=$?
  done
  echo "etcdctl returned sucessfully, continuing"

  mkdir -p /opt/ibm/wlp/usr/servers/$SERVERDIRNAME/resources/security
  cd /opt/ibm/wlp/usr/servers/$SERVERDIRNAME/resources/
  etcdctl get /proxy/third-party-ssl-cert > cert.pem
  openssl pkcs12 -passin pass:keystore -passout pass:keystore -export -out cert.pkcs12 -in cert.pem
  keytool -import -v -trustcacerts -alias default -file cert.pem -storepass truststore -keypass keystore -noprompt -keystore security/truststore.jks
  keytool -genkey -storepass testOnlyKeystore -keypass wefwef -keyalg RSA -alias endeca -keystore security/key.jks -dname CN=rsssl,OU=unknown,O=unknown,L=unknown,ST=unknown,C=CA
  keytool -delete -storepass testOnlyKeystore -alias endeca -keystore security/key.jks
  keytool -v -importkeystore -srcalias 1 -alias 1 -destalias default -noprompt -srcstorepass keystore -deststorepass testOnlyKeystore -srckeypass keystore -destkeypass testOnlyKeystore -srckeystore cert.pkcs12 -srcstoretype PKCS12 -destkeystore security/key.jks -deststoretype JKS

  export MAP_KEY=$(etcdctl get /passwords/map-key)
  export MAP_SERVICE_URL=$(etcdctl get /map/url)
  export PLAYER_SERVICE_URL=$(etcdctl get /player/url)
  export LOGSTASH_ENDPOINT=$(etcdctl get /logstash/endpoint)
  export LOGMET_HOST=$(etcdctl get /logmet/host)
  export LOGMET_PORT=$(etcdctl get /logmet/port)
  export LOGMET_TENANT=$(etcdctl get /logmet/tenant)
  export LOGMET_PWD=$(etcdctl get /logmet/pwd)
  export SYSTEM_ID=$(etcdctl get /global/system_id)

  # Softlayer needs a logstash endpoint so we set up the server
  # to run in the background and the primary task is running the
  # forwarder. In ICS, Liberty is the primary task so we need to
  # run it in the foreground
  if [ "$LOGSTASH_ENDPOINT" != "" ]; then
    /opt/ibm/wlp/bin/server start $SERVERDIRNAME
    echo Starting the logstash forwarder...
    sed -i s/PLACEHOLDER_LOGHOST/$LOGSTASH_ENDPOINT/g /opt/forwarder.conf
    cd /opt
    chmod +x ./forwarder
    etcdctl get /logstash/cert > logstash-forwarder.crt
    etcdctl get /logstash/key > logstash-forwarder.key
    sleep 0.5
    ./forwarder --config ./forwarder.conf
  else
    /opt/ibm/wlp/bin/server run $SERVERDIRNAME
  fi
else
  exec a8sidecar --log --proxy --register --supervise /opt/ibm/wlp/bin/server run $SERVERDIRNAME
fi
