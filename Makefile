default: start


###############################################################
# Public objective
###############################################################
# create a new cluster
new: clean start upload init

# write dns record to your own host, sudo required
dns:
	if ! grep --quiet "pigsty dns records" /etc/hosts ; then cat files/pigsty_dns >> /etc/hosts; fi

# cache / upload rpm packages (this is useful for accelerate or perform offline installation)
cache:
	rm -rf pkg/* && mkdir -p pkg;
	ssh -t meta "sudo tar -zcf /tmp/pkg.tgz -C /www pigsty; sudo chmod a+r /tmp/pkg.tgz"
	scp -r meta:/tmp/pkg.tgz pkg.tgz
	ssh -t meta "sudo rm -rf /tmp/pkg.tgz"

# upload rpm cache to meta node
upload:
	ssh -t meta "sudo rm -rf /tmp/pkg.tgz"
	scp -r pkg.tgz meta:/tmp/pkg.tgz
	ssh -t meta "sudo mkdir -p /www/pigsty/; sudo rm -rf /www/pigsty/*; sudo tar -xf /tmp/pkg.tgz --strip-component=1 -C /www/pigsty/"

# init will pull up entire cluster
init:
	./infra.yml
	./initdb.yml 				# provision pg-test and pg-meta

# down will halt all vm (not destroy)
down: halt

# show vagrant cluster status
st: status


###############################################################
# vm management
###############################################################
clean:
	cd vagrant && vagrant destroy -f --parallel; exit 0
up:
	cd vagrant && vagrant up
mt:
	cd vagrant && vagrant up meta
halt:
	cd vagrant && vagrant halt
status:
	cd vagrant && vagrant status
suspend:
	cd vagrant && vagrant suspend
resume:
	cd vagrant && vagrant resume
provision:
	cd vagrant && vagrant provision
# sync ntp time (only works after ntp been installed during init-node)
sync2:
	echo meta node-1 node-2 node-3 | xargs -n1 -P4 -I{} ssh {} 'sudo chronyc -a makestep'; true
sync:
	echo meta node-1 node-2 node-3 | xargs -n1 -P4 -I{} ssh {} 'sudo ntpdate pool.ntp.org'; true
# append pigsty ssh config to ~/.ssh
ssh:
	cd vagrant && vagrant ssh-config > ~/.ssh/pigsty_config 2>/dev/null; true
	if ! grep --quiet "pigsty_config" ~/.ssh/config ; then (echo 'Include ~/.ssh/pigsty_config' && cat ~/.ssh/config) >  ~/.ssh/config.tmp; mv ~/.ssh/config.tmp ~/.ssh/config && chmod 0600 ~/.ssh/config; fi
	if ! grep --quiet "StrictHostKeyChecking=no" ~/.ssh/config ; then (echo 'StrictHostKeyChecking=no' && cat ~/.ssh/config) >  ~/.ssh/config.tmp; mv ~/.ssh/config.tmp ~/.ssh/config && chmod 0600 ~/.ssh/config; fi

start: up ssh sync
stop: halt


###############################################################
# pgbench (init/read-write/read-only)
###############################################################
ri:
	pgbench -is10 postgres://test:test@pg-test:5433/test
rw:
	while true; do pgbench -nv -P1 -c2 --rate=50 -T10 postgres://test:test@pg-test:5433/test; done
ro:
	while true; do pgbench -nv -P1 -c4 --select-only --rate=1000 -T10 postgres://test:test@pg-test:5434/test; done
rw2:
	while true; do pgbench -nv -P1 -c2 -T10 postgres://test:test@pg-test:5433/test; done
ro2:
	while true; do pgbench -nv -P1 -c8 -T10 --select-only postgres://test:test@pg-test:5434/test; done
rl:
	ssh -t node-1 "sudo -iu postgres patronictl -c /pg/bin/patroni.yml list -W"
r1:
	ssh -t node-1 "sudo reboot"
r2:
	ssh -t node-2 "sudo reboot"
r3:
	ssh -t node-3 "sudo reboot"
ckpt:
	ansible all -b --become-user=postgres -a "psql -c 'CHECKPOINT;'"
gis:
	# psql postgres://test:test@pg-test:5433/test -c 'CREATE EXTENSION postgis;'
	psql postgres://test:test@pg-test:5433/test -f files/adcode.sql

###############################################################
# grafna management
###############################################################
view:
	open -n 'http://grafana.pigsty/d/pg-cluster/pg-cluster?refresh=5s&var-cls=pg-test'

ha:
	open -n 'http://pg-test:9101/haproxy'

dump-monitor:
	ssh meta "sudo cp /var/lib/grafana/grafana.db /tmp/grafana.db; sudo chmod a+r /tmp/grafana.db"
	scp meta:/tmp/grafana.db roles/grafana/files/grafana/grafana.db
	ssh meta "sudo rm -rf /tmp/grafana.db"

restore-monitor:
	scp files/grafana/grafana.db meta:/tmp/grafana.db
	ssh meta "sudo mv /tmp/grafana.db /var/lib/grafana/grafana.db;sudo chown grafana /var/lib/grafana/grafana.db"
	ssh meta "sudo rm -rf /etc/grafana/provisioning/dashboards/* ;sudo systemctl restart grafana-server"



###############################################################
# environment management
###############################################################
env: env-dev

env-clean:
	rm -rf cls/inventory.ini
	rm -rf group_vars/all.yml

env-dev: env-clean
	ln -s dev.ini cls/inventory.ini
	ln -s dev.yml group_vars/all.yml

env-test: env-clean
	ln -s test.ini cls/inventory.ini
	ln -s test.yml group_vars/all.yml

env-prod: env-clean
	ln -s prod.ini cls/inventory.ini
	ln -s prod.yml group_vars/all.yml

###############################################################
# kubernetes management
###############################################################
# open kubernetes dashboard
k8s:
	./init-k8s.yml

kd:
	open -n 'http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/'

k-conf:
	ssh meta 'sudo cat /etc/kubernetes/admin.conf' > ~/.kube/config

# copy kubernetes admin token to files/admin.token
k-token:
	# ssh meta 'kubectl get secret $(kubectl get sa dashboard-admin-sa -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode' | pbcopy
	ssh meta 'kubectl get secret $(kubectl get sa dashboard-admin-sa -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode' > files/admin.token

.PHONY: default ssh dns cache init node meta infra clean up halt status suspend resume start stop down new
