# Metronome
This branch introduces the Metronome changes such that only the shuffled subset is getting persisted in the WAL of etcd. The original etcd implementation is left on `main` and a branch `no-wal` is an implementation where no entries are persisted.

## Local benchmark
0. Reload environment variables:
```bash
$ git checkout metronome
```
1. Checkout the `metronome` branch.
```bash
$ git checkout metronome
```
2. Build
```bash
$ make
```
3. Generate `Procfile` for `N` nodes
```bash
$ ./generate_procfile.sh <N>
```
4. Spawn up a local cluster (more info on goreman [here](https://github.com/etcd-io/etcd/tree/main?tab=readme-ov-file#running-a-local-etcd-cluster)):
```bash
$ goreman start
```
5. Run [benchmark](https://etcd.io/docs/v3.5/benchmarks/etcd-3-demo-benchmarks/)
```bash
$ go run ./tools/benchmark put
```
6. Clean up the WAL files
```bash
$ ./clean_local.sh
```