package walutil

import (
	"fmt"
	"go.etcd.io/etcd/server/v3/storage/wal"
	"go.etcd.io/etcd/server/v3/storage/wal/walpb"
	"go.etcd.io/raft/v3/raftpb"
	"go.uber.org/zap"
	"io"
	"os"
	"path/filepath"
	"sort"
)

// ReadAllWithMissingIndexes reads all entries from the WAL and identifies missing indexes.
func ReadAllWithMissingIndexes(walDir string) (NodeWAL, []uint64, error) {
	nodeWAL := NodeWAL{
		NodeName: filepath.Base(walDir),
	}

	lg, err := zap.NewProduction()
	if err != nil {
		return nodeWAL, nil, fmt.Errorf("failed to create logger: %w", err)
	}
	defer lg.Sync()

	walsnap := walpb.Snapshot{}
	w, err := wal.Open(lg, walDir, walsnap)
	if err != nil {
		return nodeWAL, nil, fmt.Errorf("error opening WAL: %w", err)
	}
	defer w.Close()

	decoder := w.GetDecoder()

	rec := &walpb.Record{}
	var (
		metadata       []byte
		state          raftpb.HardState
		entries        []raftpb.Entry
		missingIndexes []uint64
	)

	var expectedIndex uint64 = walsnap.Index + 1

	for err = decoder.Decode(rec); err == nil; err = decoder.Decode(rec) {
		switch rec.Type {
		case wal.EntryType:
			e := raftpb.Entry{}
			e.Unmarshal(rec.Data)

			// Check for missing indexes
			for expectedIndex < e.Index {
				missingIndexes = append(missingIndexes, expectedIndex)
				expectedIndex++
			}

			entries = append(entries, e)
			expectedIndex = e.Index + 1

		case wal.StateType:
			state.Unmarshal(rec.Data)

		case wal.MetadataType:
			metadata = rec.Data

		case wal.CrcType:
			// Handle CRC validation if necessary

		default:
			// Handle other types if necessary
		}
	}

	if err != nil && err != io.EOF {
		return nodeWAL, nil, fmt.Errorf("error reading WAL: %w", err)
	}

	nodeWAL.Metadata = metadata
	nodeWAL.State = state
	nodeWAL.Entries = entries

	return nodeWAL, missingIndexes, nil
}

// ReadWAL reads the WAL entries from a given directory
func ReadWAL(walDir string) (NodeWAL, error) {
	nodeWAL := NodeWAL{
		NodeName: filepath.Base(walDir),
	}

	lg, err := zap.NewProduction()
	if err != nil {
		return nodeWAL, fmt.Errorf("failed to create logger: %w", err)
	}
	defer lg.Sync()

	walsnap := walpb.Snapshot{}
	w, err := wal.Open(lg, walDir, walsnap)
	if err != nil {
		return nodeWAL, fmt.Errorf("error opening WAL: %w", err)
	}
	defer w.Close()

	metadata, state, entries, err := w.ReadAll()
	if err != nil && err != io.EOF {
		return nodeWAL, fmt.Errorf("error reading WAL entries: %w", err)
	}

	nodeWAL.Metadata = metadata
	nodeWAL.State = state
	nodeWAL.Entries = entries

	return nodeWAL, nil
}

// writeWAL writes a NodeWAL to the specified WAL directory
func WriteWAL(walDir string, nodeWAL NodeWAL) error {
	lg, err := zap.NewProduction()
	if err != nil {
		return fmt.Errorf("failed to create logger: %w", err)
	}
	defer lg.Sync()

	if err := os.RemoveAll(walDir); err != nil {
		return fmt.Errorf("failed to remove existing WAL directory: %w", err)
	}

	if err := os.MkdirAll(walDir, 0750); err != nil {
		return fmt.Errorf("failed to create WAL directory: %w", err)
	}

	w, err := wal.Create(lg, walDir, nodeWAL.Metadata)
	if err != nil {
		return fmt.Errorf("failed to create WAL: %w", err)
	}
	defer w.Close()

	return w.Save(nodeWAL.State, nodeWAL.Entries)
}

// filterWAL filters a NodeWAL to keep only every Nth entry.
func FilterWAL(nodeWAL NodeWAL, N int) NodeWAL {
	var filteredEntries []raftpb.Entry
	for i, entry := range nodeWAL.Entries {
		if i%N == 0 {
			filteredEntries = append(filteredEntries, entry)
		}
	}
	return NodeWAL{
		NodeName: nodeWAL.NodeName,
		Metadata: nodeWAL.Metadata,
		State:    nodeWAL.State,
		Entries:  filteredEntries,
	}
}

// mergeEntries merges missing entries into recovering NodeWAL
func MergeEntries(recovering NodeWAL, missingEntries []raftpb.Entry) NodeWAL {
	allEntries := append(recovering.Entries, missingEntries...)
	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].Index < allEntries[j].Index
	})

	// Deduplicate entries by Index
	dedupedEntries := make([]raftpb.Entry, 0, len(allEntries))
	indexMap := make(map[uint64]bool)
	for _, entry := range allEntries {
		if !indexMap[entry.Index] {
			dedupedEntries = append(dedupedEntries, entry)
			indexMap[entry.Index] = true
		}
	}

	return NodeWAL{
		NodeName: recovering.NodeName,
		Metadata: recovering.Metadata,
		State:    recovering.State,
		Entries:  dedupedEntries,
	}
}

// updateHardState updates the HardState based on the entries
func UpdateHardState(nodeWAL *NodeWAL) {
	if len(nodeWAL.Entries) == 0 {
		return
	}
	lastEntry := nodeWAL.Entries[len(nodeWAL.Entries)-1]
	nodeWAL.State.Commit = lastEntry.Index
	nodeWAL.State.Term = lastEntry.Term
}

// EntrySource represents an entry and its source node.
type EntrySource struct {
	Entry raftpb.Entry
	Node  string
}
