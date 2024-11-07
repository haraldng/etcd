./server --mode=recover --port=50052 --data-dir=/Users/haraldng/code/etcd/metro_recovery/example/infra2/member/wal --peers-file=/Users/haraldng/code/etcd/metro_recovery/example/peers.txt --ip=localhost


protoc -I=. -I=$GOPATH/pkg/mod/github.com/gogo/protobuf@v1.3.2 --gogofaster_out=plugins=grpc:. recover_wal.proto   

go build -o server    

bin/etcd --name infra2 --listen-client-urls http://127.0.0.1:12379 --advertise-client-urls http://127.0.0.1:12379 --listen-peer-urls http://127.0.0.1:12380 --initial-advertise-peer-urls http://127.0.0.1:12380 --initial-cluster-token etcd-cluster-1 --initial-cluster 'infra1=http://127.0.0.1:2380,infra2=http://127.0.0.1:12380,infra3=http://127.0.0.1:22380' --initial-cluster-state new --logger=zap --log-outputs=stderr --data-dir local_test/infra2 --log-level error --quota-backend-bytes=5368709120