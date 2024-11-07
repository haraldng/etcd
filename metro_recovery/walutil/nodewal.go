package walutil

import (
	"go.etcd.io/raft/v3/raftpb"
)

// NodeWAL represents the WAL data of a node
type NodeWAL struct {
	NodeName string           // Name of the node
	Metadata []byte           // Metadata associated with the WAL
	State    raftpb.HardState // Raft HardState of the WAL
	Entries  []raftpb.Entry   // Log entries in the WAL
}
