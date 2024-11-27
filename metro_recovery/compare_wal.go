package main

import (
	"fmt"
	"go.etcd.io/etcd/server/v3/storage/wal"
	"go.etcd.io/etcd/server/v3/storage/wal/walpb"
	"go.etcd.io/raft/v3/raftpb"
	"go.uber.org/zap"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// NodeWAL represents the WAL data of a node
type NodeWAL struct {
	NodeName string
	Entries  []raftpb.Entry
}

func main() {
	if len(os.Args) < 2 {
		fmt.Printf("Usage: %s <wal_dir_node1> <wal_dir_node2> ...\n", filepath.Base(os.Args[0]))
		fmt.Println("Compare WAL files between multiple nodes.")
		os.Exit(1)
	}

	// Read WAL data from each node's WAL directory
	var nodeWALs []NodeWAL
	for _, dir := range os.Args[1:] {
		nodeName := filepath.Base(dir)
		fmt.Printf("Processing WAL for node: %s (directory: %s)\n", nodeName, dir)

		entries, err := readWAL(dir)
		if err != nil {
			log.Fatalf("Failed to read WAL for node %s: %v", nodeName, err)
		}

		nodeWALs = append(nodeWALs, NodeWAL{
			NodeName: nodeName,
			Entries:  entries,
		})
		fmt.Printf("Node %s has %d entries.\n", nodeName, len(entries))
	}

	filteredWAL := filterWAL(nodeWALs[0], 2)
	/*
		// Compare WAL entries between nodes
		fmt.Println("\nComparing WAL entries between nodes...")
		for i := 0; i < len(nodeWALs); i++ {
			for j := i + 1; j < len(nodeWALs); j++ {
				compareWALs(nodeWALs[i], nodeWALs[j])
			}
		}
		fmt.Println("\nComparing WAL entries with filtered WAL...")
		compareWALs(nodeWALs[0], filteredWAL)
	*/

	missingEntries := findAndFillGaps(filteredWAL, nodeWALs[1])
	mergedWAL := mergeEntries(filteredWAL, missingEntries)
	fmt.Println("\nComparing WALs after merging...")
	compareWALs(nodeWALs[0], mergedWAL)
}

// readWAL reads the WAL entries from a given directory
func readWAL(walDir string) ([]raftpb.Entry, error) {
	// Create a new zap.Logger for logging
	lg, err := zap.NewProduction() // Or use zap.NewExample() for simpler output
	if err != nil {
		return nil, fmt.Errorf("failed to create logger: %w", err)
	}
	defer lg.Sync() // Ensure logs are flushed before exiting

	// Specify an empty snapshot (you can customize this if needed)
	walsnap := walpb.Snapshot{}

	// Open the WAL directory
	w, err := wal.Open(lg, walDir, walsnap)
	if err != nil {
		return nil, fmt.Errorf("error opening WAL: %w", err)
	}
	defer w.Close()

	// Read all entries
	_, _, entries, err := w.ReadAll() // metadata, hs,
	if err != nil {
		return nil, fmt.Errorf("error reading WAL entries: %w", err)
	}

	return entries, nil
}

// compareWALs compares the entries of two nodes and reports differences
func compareWALs(node1, node2 NodeWAL) {
	fmt.Printf("Comparing %s and %s:\n", node1.NodeName, node2.NodeName)

	entries1 := node1.Entries
	entries2 := node2.Entries

	// Find the smaller size
	minSize := len(entries1)
	if len(entries2) < minSize {
		minSize = len(entries2)
	}

	for i := 0; i < minSize; i++ {
		e1 := entries1[i]
		e2 := entries2[i]

		if e1.Index != e2.Index || e1.Term != e2.Term || !strings.EqualFold(string(e1.Data), string(e2.Data)) {
			fmt.Printf("Difference at entry %d:\n", i+1)
			fmt.Printf("  node1: Index=%d, Term=%d\n", e1.Index, e1.Term)
			fmt.Printf("  node2: Index=%d, Term=%d\n", e2.Index, e2.Term)
		}

	}

	// Check for extra entries
	if len(entries1) > minSize {
		fmt.Printf("Extra entries in %s:\n", node1.NodeName)
		for _, e := range entries1[minSize:] {
			fmt.Printf("  Index=%d, Term=%d, Data=%s\n", e.Index, e.Term, string(e.Data))
		}
	} else if len(entries2) > minSize {
		fmt.Printf("Extra entries in %s:\n", node2.NodeName)
		for _, e := range entries2[minSize:] {
			fmt.Printf("  Index=%d, Term=%d, Data=%s\n", e.Index, e.Term, string(e.Data))
		}
	}
}

// filterNodeWAL filters a NodeWAL to keep only every Nth entry.
func filterWAL(nodeWAL NodeWAL, N int) NodeWAL {
	var filteredEntries []raftpb.Entry

	for i, entry := range nodeWAL.Entries {
		if i%N == 0 {
			filteredEntries = append(filteredEntries, entry)
		}
	}

	// Return a new NodeWAL with the filtered entries
	return NodeWAL{
		NodeName: nodeWAL.NodeName,
		Entries:  filteredEntries,
	}
}

// findAndFillGaps identifies gaps in the indices of a NodeWAL and retrieves
// the missing entries from another NodeWAL.
func findAndFillGaps(recovering NodeWAL, provider NodeWAL) []raftpb.Entry {
	// Create a map for quick lookup of provider entries by Index
	backupEntries := make(map[uint64]raftpb.Entry)
	for _, entry := range provider.Entries {
		backupEntries[entry.Index] = entry
	}

	// Find gaps in the recovering WAL
	var missingEntries []raftpb.Entry
	for i := 0; i < len(recovering.Entries)-1; i++ {
		currentIndex := recovering.Entries[i].Index
		nextIndex := recovering.Entries[i+1].Index

		// If there is a gap, identify the missing indices
		for missingIndex := currentIndex + 1; missingIndex < nextIndex; missingIndex++ {
			if backupEntry, exists := backupEntries[missingIndex]; exists {
				missingEntries = append(missingEntries, backupEntry)
			} else {
				fmt.Printf("Index %d missing in both recovering and provider WALs.\n", missingIndex)
			}
		}
	}

	// Check if there are gaps after the last entry in the recovering WAL
	if len(recovering.Entries) > 0 {
		lastIndex := recovering.Entries[len(recovering.Entries)-1].Index
		for _, backupEntry := range provider.Entries {
			if backupEntry.Index > lastIndex {
				missingEntries = append(missingEntries, backupEntry)
			}
		}
	}

	return missingEntries
}

func mergeEntries(recovering NodeWAL, missingEntries []raftpb.Entry) NodeWAL {
	allEntries := append(recovering.Entries, missingEntries...)

	// Sort the entries by Index
	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].Index < allEntries[j].Index
	})

	// Return a new NodeWAL with the merged entries
	return NodeWAL{
		NodeName: recovering.NodeName,
		Entries:  allEntries,
	}
}

// Function to get the latest WAL file
func getLatestWALFile(walDir string) (string, error) {
	files, err := ioutil.ReadDir(walDir)
	if err != nil {
		return "", err
	}

	var walFiles []string
	for _, file := range files {
		if strings.HasSuffix(file.Name(), ".wal") {
			walFiles = append(walFiles, file.Name())
		}
	}

	if len(walFiles) == 0 {
		return "", fmt.Errorf("no WAL files found in %s", walDir)
	}

	// Sort WAL files based on sequence number
	sort.Strings(walFiles)
	latestWAL := walFiles[len(walFiles)-1]
	return filepath.Join(walDir, latestWAL), nil
}
