package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"

	"go.etcd.io/etcd/v3/metro_recovery/walutil"
	"go.etcd.io/raft/v3/raftpb"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Printf("Usage: %s <providerWAL> <incompleteWAL>\n", filepath.Base(os.Args[0]))
		fmt.Println("Merges missing WAL entries from providerWAL into incompleteWAL.")
		os.Exit(1)
	}

	providerWALDir := os.Args[1]
	incompleteWALDir := os.Args[2]

	fmt.Printf("Merging WALs:\n- Provider WAL: %s\n- Incomplete WAL: %s\n", providerWALDir, incompleteWALDir)

	// Read provider WAL
	providerWAL, err := walutil.ReadWAL(providerWALDir)
	if err != nil {
		log.Fatalf("Failed to read provider WAL: %v", err)
	}

	// Read incomplete WAL
	incompleteWAL, err := walutil.ReadWAL(incompleteWALDir)
	if err != nil {
		log.Fatalf("Failed to read incomplete WAL: %v", err)
	}

	// Find missing entries
	fmt.Println("Identifying missing entries in incomplete WAL...")
	missingEntries := findMissingEntries(incompleteWAL, providerWAL)

	// Merge missing entries into incomplete WAL
	fmt.Println("Merging missing entries...")
	mergedWAL := mergeEntries(incompleteWAL, missingEntries)

	// Update HardState to ensure consistency
	walutil.UpdateHardState(&mergedWAL)

	// Write the merged WAL back to the incomplete WAL directory
	fmt.Println("Writing merged WAL...")
	if err := walutil.WriteWAL(incompleteWALDir, mergedWAL); err != nil {
		log.Fatalf("Failed to write merged WAL: %v", err)
	}

	fmt.Printf("Merged WAL written successfully to: %s\n", incompleteWALDir)
}

// findMissingEntries finds the entries in providerWAL that are missing in incompleteWAL.
func findMissingEntries(incompleteWAL, providerWAL walutil.NodeWAL) []raftpb.Entry {
	// Create a map of existing entries in the incomplete WAL for quick lookup
	existingEntries := make(map[uint64]struct{})
	for _, entry := range incompleteWAL.Entries {
		existingEntries[entry.Index] = struct{}{}
	}

	// Identify missing entries
	var missingEntries []raftpb.Entry
	for _, entry := range providerWAL.Entries {
		if _, exists := existingEntries[entry.Index]; !exists {
			missingEntries = append(missingEntries, entry)
		}
	}

	fmt.Printf("Found %d missing entries.\n", len(missingEntries))
	return missingEntries
}

// mergeEntries merges the missing entries into the incomplete WAL, ensuring a sorted order.
func mergeEntries(incompleteWAL walutil.NodeWAL, missingEntries []raftpb.Entry) walutil.NodeWAL {
	// Combine existing entries with missing entries
	allEntries := append(incompleteWAL.Entries, missingEntries...)

	// Sort all entries by index
	sort.Slice(allEntries, func(i, j int) bool {
		return allEntries[i].Index < allEntries[j].Index
	})

	// Deduplicate entries by index
	deduplicatedEntries := deduplicateEntries(allEntries)

	// Return a new NodeWAL with merged entries
	return walutil.NodeWAL{
		NodeName: incompleteWAL.NodeName,
		Metadata: incompleteWAL.Metadata,
		State:    incompleteWAL.State,
		Entries:  deduplicatedEntries,
	}
}

// deduplicateEntries removes duplicate entries based on their index, keeping the first occurrence.
func deduplicateEntries(entries []raftpb.Entry) []raftpb.Entry {
	indexSeen := make(map[uint64]bool)
	var deduplicated []raftpb.Entry

	for _, entry := range entries {
		if !indexSeen[entry.Index] {
			deduplicated = append(deduplicated, entry)
			indexSeen[entry.Index] = true
		}
	}

	return deduplicated
}
